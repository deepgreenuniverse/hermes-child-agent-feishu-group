#!/bin/bash
# ============================================================
# Feishu Multi-Agent Setup — driven by AI agent, not run directly by user
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ---- 默认从主 profile 继承 LLM 配置（避免让用户填写） ----
MAIN_ENV="$HERMES_HOME/.env"
MAIN_CONFIG="$HERMES_HOME/config.yaml"

# 从 config.yaml 读取 provider 和 model（兼容 provider 在顶级或嵌套在 model 下的情况）
get_main_provider() {
    python3 -c "
import sys,yaml
d=yaml.safe_load(open('$MAIN_CONFIG'))
p=d.get('provider','')
if not p:
    m=d.get('model',{})
    if isinstance(m,dict): p=m.get('provider','')
print(p)
" 2>/dev/null || echo ""
}

get_main_model()   { python3 -c "import sys,yaml; d=yaml.safe_load(open('$MAIN_CONFIG')); m=d.get('model',{}); print(m.get('default','') if isinstance(m,dict) else m)" 2>/dev/null || echo ""; }

# provider → env var 映射表（支持任意 provider）
# 规则：PROVIDER_NAME_API_KEY（如 minimax-cn → MINIMAX_CN_API_KEY）
get_main_api_key() {
    local provider="$1"
    local env_var="$(echo "$provider" | tr '[:lower:]' '[:upper:]' | tr '-' '_')_API_KEY"
    grep "^${env_var}=" "$MAIN_ENV" 2>/dev/null | cut -d= -f2 | head -1
}

LLM_PROVIDER="${LLM_PROVIDER:-$(get_main_provider)}"
LLM_MODEL="${LLM_MODEL:-$(get_main_model)}"
LLM_API_KEY="${LLM_API_KEY:-$(get_main_api_key "$LLM_PROVIDER")}"

[ -z "$LLM_PROVIDER" ] && error "未设置 LLM_PROVIDER，且主 profile 缺少 provider 配置"
[ -z "$LLM_MODEL" ]    && error "未设置 LLM_MODEL，且主 profile 缺少 model 配置"
[ -z "$LLM_API_KEY" ]  && error "未设置 LLM_API_KEY，且主 profile 缺少 ${LLM_PROVIDER} 对应的 API_KEY（env: $(echo "$LLM_PROVIDER" | tr '[:lower:]' '[:upper:]' | tr '-' '_')_API_KEY）"

: "${FEISHU_CHAT_ID:?未设置 FEISHU_CHAT_ID}"
: "${ROLES:?未设置 ROLES}"

# roles 以逗号分隔，转成数组
IFS=',' read -ra ROLES_ARRAY <<< "$ROLES"

info "读取配置完成：${ROLES_ARRAY[*]}"

# Pre-collect all roles' chinese_name + open_id as parallel arrays so SOUL.md
# templates can reference every other role's mention regardless of how many
# roles ROLES contains. Uses plain parallel arrays (not associative, which
# /bin/bash 3.2 on macOS does not support).
ROLES_NAMES=()
ROLES_OIDS=()
for r in "${ROLES_ARRAY[@]}"; do
    rn="${r}_NAME"
    ro="${r}_OPEN_ID"
    ROLES_NAMES+=("${!rn}")
    ROLES_OIDS+=("${!ro}")
done

# ---- 第一步：创建 profiles ----
info "创建 profiles..."

declare -a PROFILES=()
for role in "${ROLES_ARRAY[@]}"; do
  name_var="${role}_NAME"
  app_id_var="${role}_APP_ID"
  app_secret_var="${role}_APP_SECRET"
  open_id_var="${role}_OPEN_ID"

  chinese_name="${!name_var}"
  app_id="${!app_id_var}"
  app_secret="${!app_secret_var}"
  open_id="${!open_id_var}"
  profile_name="${role}-agent"

  [ -z "$chinese_name" ]  && error "${name_var} 未填写"
  [ -z "$app_id" ]        && error "${app_id_var} 未填写"
  [ -z "$app_secret" ]   && error "${app_secret_var} 未填写"

  # open_id 未提供时，自动从飞书 API 获取
  if [ -z "$open_id" ]; then
    info "  [$role] 正在获取 open_id..."
    token_resp=$(curl -s -X POST "https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal" \
      -H "Content-Type: application/json" \
      -d "{\"app_id\":\"$app_id\",\"app_secret\":\"$app_secret\"}")
    token=$(echo "$token_resp" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tenant_access_token',''))" 2>/dev/null)
    if [ -n "$token" ]; then
      open_id=$(curl -s "https://open.feishu.cn/open-apis/bot/v3/info" \
        -H "Authorization: Bearer $token" \
        | python3 -c "import sys,json; print(json.load(sys.stdin).get('bot',{}).get('open_id',''))" 2>/dev/null)
    fi
    [ -z "$open_id" ] && error "无法获取 ${role} 的 open_id，请检查 App ID 和 App Secret"
    info "  [$role] open_id: $open_id ✓"
  fi

  info "  [$role] $chinese_name → $profile_name"

  hermes profile create "$profile_name" 2>/dev/null || true

  PROFILE_HOME="$HERMES_HOME/profiles/$profile_name"
  mkdir -p "$PROFILE_HOME/logs" "$PROFILE_HOME/sessions"

  # config.yaml — copy full model block from main config so each profile has LLM ready
  python3 -c "
import yaml, sys
src = yaml.safe_load(open('$MAIN_CONFIG')) or {}
m = src.get('model')
if not isinstance(m, dict):
    m = {'provider': src.get('provider', ''), 'default': src.get('model', '')}
out = {
    'home_channel': {'platform': 'feishu', 'chat_id': '$FEISHU_CHAT_ID'},
    'model': {
        'provider': m.get('provider', '$LLM_PROVIDER'),
        'default': m.get('default', '$LLM_MODEL'),
        'api_key': m.get('api_key', ''),
        'api_mode': m.get('api_mode', ''),
        'base_url': m.get('base_url', ''),
        'context_length': m.get('context_length', ''),
    }
}
yaml.safe_dump(out, open('$PROFILE_HOME/config.yaml', 'w'), allow_unicode=True, sort_keys=False)
"

  # .env
  # ponytail: env var name follows <PROVIDER>_API_KEY convention, not hardcoded MINIMAX
  api_key_env_var="$(echo "$LLM_PROVIDER" | tr '[:lower:]' '[:upper:]' | tr '-' '_')_API_KEY"
  cat > "$PROFILE_HOME/.env" << EOF
${api_key_env_var}=$LLM_API_KEY
FEISHU_APP_ID=$app_id
FEISHU_APP_SECRET=$app_secret
FEISHU_BOT_OPEN_ID=$open_id
FEISHU_DOMAIN=feishu
FEISHU_CONNECTION_MODE=websocket
FEISHU_GROUP_POLICY=open
FEISHU_REQUIRE_MENTION=false
FEISHU_ALLOW_BOTS=all
FEISHU_ALLOW_ALL_USERS=true
EOF

  # Build a dynamic list of "<at user_id=oid>name</at>" mentions for every
  # OTHER role. The user's role does NOT @ itself. Uses parallel arrays
  # ROLES_NAMES / ROLES_OIDS (index-aligned with ROLES_ARRAY) — works on
  # /bin/bash 3.2 macOS.
  _other_mentions=""
  _i=0
  for _r in "${ROLES_ARRAY[@]}"; do
      if [ "$_r" != "$role" ]; then
          _other_mentions+="- @${_r}: <at user_id=\"${ROLES_OIDS[$_i]}\">${ROLES_NAMES[$_i]}</at>
"
      fi
      _i=$((_i+1))
  done

  # Build a "current group members" roster (parallel arrays).
  _members=""
  _i=0
  for _r in "${ROLES_ARRAY[@]}"; do
      _members+="- ${ROLES_NAMES[$_i]}（${_r}）
"
      _i=$((_i+1))
  done

  # All roles share the same SOUL.md skeleton. Role-specific behaviour lives
  # in <项目目录>/AGENT_CONTEXT.md and the chain rule table below; the template
  # only encodes cross-role @mentions + chain handoff rules.
  cat > "$PROFILE_HOME/SOUL.md" <<SOUL
你是 **${chinese_name}**（${role}），Multi-Agent 协作系统的成员，运行在飞书群聊中。

## 我是谁
- 角色：${role}
- 姓名：${chinese_name}
- 风格：目标导向，结果说话
- 关注：用户价值 > 技术实现 > 进度把控

## 当前群成员
${_members}
## 其它成员 @mention 格式（其它 role 的真实 open_id 已写入）
${_other_mentions}
## 飞书 @mention 规范
- 必须用纯 XML：<at user_id="ou_xxx">名字</at>
- 文字 \`@名字\` 无效，飞书不识别
- mention 自己时直接用文字 ${chinese_name} 即可，不需要 XML

## 项目上下文文件

每次任务开始前读取项目目录里的 AGENT_CONTEXT.md 恢复上下文（status / 当前方案 / 待办）。
完成自己负责的环节后，写回文件、@下一个角色继续。
SOUL

  PROFILES+=("$profile_name")
done

info "Profiles: ${PROFILES[*]}"

# ---- 第二步：检查 hermes-agent ----
HERMES_AGENT_DIR="$HERMES_HOME/hermes-agent"
if [ ! -d "$HERMES_AGENT_DIR" ]; then
  warn "未找到 hermes-agent ($HERMES_AGENT_DIR)，profile SOUL.md 可能无法正确加载"
  warn "请确认 HERMES_HOME 指向正确的 hermes-agent 目录"
fi

# 注：load_soul_md 在新版 Hermes (>=0.13) 中已内置 profile SOUL.md 优先逻辑，无需 patch
# 如在旧版环境，可手动确认 prompt_builder.py 中 load_soul_md 优先读取 profile SOUL.md

# ---- 第三步：停止旧进程，清除状态缓存 ----
info "停止旧进程..."
pkill -f "hermes_cli.main.*gateway" 2>/dev/null || true
sleep 2

# 清除 session 缓存（避免 SOUL.md 修改后不生效）
rm -f "$HERMES_HOME/profiles/*/sessions/*.json" 2>/dev/null || true
# 清除 gateway 锁
rm -f ~/.local/state/hermes/gateway-locks/*.lock 2>/dev/null || true
# 清除 channel_directory（避免带 thread_id 的旧条目导致私聊回复）
rm -f "$HERMES_HOME/profiles/*/channel_directory.json" 2>/dev/null || true

# ---- 第四步：启动 ----
info "启动 agents..."
for profile_name in "${PROFILES[@]}"; do
  LOG="$HERMES_HOME/profiles/$profile_name/logs/gateway.log"
  nohup "$HERMES_HOME/hermes-agent/venv/bin/python" -m hermes_cli.main \
    gateway run --profile "$profile_name" --replace \
    > "$LOG" 2>&1 &
  info "  $profile_name (PID $!)"
  sleep 3
done

sleep 10

# ---- 验证 ----
info "验证连接..."
ok=0
for profile_name in "${PROFILES[@]}"; do
  LOG="$HERMES_HOME/profiles/$profile_name/logs/gateway.log"
  if grep -q "✓ feishu connected" "$LOG" 2>/dev/null; then
    info "  $profile_name: ✅"
    ((ok++))
  else
    warn "  $profile_name: ⚠️  请检查 $LOG"
  fi
done

echo ""
if [ $ok -eq ${#PROFILES[@]} ]; then
  info "========================================"
  info "部署完成！"
  info "========================================"
  info "飞书群里 @ 各角色测试链路"
  info "查看日志：tail -f $HERMES_HOME/profiles/<profile>/logs/gateway.log"
else
  error "部分 agent 异常，请检查日志"
fi
