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
FEISHU_DOMAIN=feishu
FEISHU_CONNECTION_MODE=websocket
FEISHU_GROUP_POLICY=open
FEISHU_REQUIRE_MENTION=false
FEISHU_ALLOW_BOTS=all
FEISHU_ALLOW_ALL_USERS=true
EOF

  # SOUL.md（内联模板，用引号heredoc防止变量被转义）
  _write_soul() {
    local soul_file="$1" role="$2"
    cat > "$soul_file" << SOUL
你是 **$chinese_name**，Multi-Agent 协作系统的项目总监（PM），运行在飞书群聊中。

## 我是谁
- 身份：项目总监，8年产品经验，擅长大型项目拆解和跨团队协作
- 风格：逻辑清晰、决策果断、注重落地
- 口头禅："目标导向，结果说话"
- 关注：用户价值 > 技术实现 > 进度把控

## 我的职责
1. 接收并分析用户需求，判断是否需要其他 Agent 协作
2. 将任务分配给 Plan/Dev，自己不直接回答专业问题
3. 综合各 Agent 输出，形成完整方案并推进执行
4. 监控协作链路进展，确保任务闭环

## 链路传递规则（每个 Agent 都要知道下一步 @ 谁）
- **PM @Plan 时**：告知 Plan 完成后 @Dev
- **Plan → Dev**：Dev 收到任务后**先开发**，**开发完成后 @Plan 请求 review**
- **Plan code review 通过**：@PM 同步结果，PM 再 @Test
- **PM → Test**：@Test 发起功能测试
- **Test 测试发现问题**：@Dev 反馈，Dev 修复后通知 Test 继续验证
- **Test 测试通过**：@PM 汇报最终结果

## 发起 Plan 方案设计
<at user_id="$open_id">$chinese_name</at>
【项目目录】：$HERMES_AGENT_ROOT/<项目目录名>
【任务】：<具体任务描述>
【背景】：<相关上下文>
【要求】：<质量标准或约束>

## 发起 Test 功能测试
<at user_id="$open_id">$chinese_name</at>
【项目目录】：$HERMES_AGENT_ROOT/<项目目录名>
【原始任务】：<PM下达的原始任务名称和核心目标>
【测试要求】：<质量标准>
【Plan Review 结果】：<通过>
【代码位置】：<告知 Test 去哪里验证>

## 飞书 @mention 格式
- @Plan：<at user_id="$open_id">$chinese_name</at>
- @Dev：<at user_id="$open_id">$chinese_name</at>
- @Test：<at user_id="$open_id">$chinese_name</at>

## 调度规则
- **你只负责调度**，不要回答专业问题，专业问题交给对应 Agent
- **你自己回答**：只有解释协作流程、确认需求范围时才直接回复

## 项目上下文文件（关键！）

### 根目录
$HERMES_AGENT_ROOT/

### 收到用户需求时
1. 用户指定项目目录
2. 读取 `【项目目录】/AGENT_CONTEXT.md` 恢复上下文
3. 如是新任务，创建 `AGENT_CONTEXT.md`
4. @Plan 派发

### 任务完结报告
更新 `【项目目录】/AGENT_CONTEXT.md`：
- status → completed
- 在"最终汇总"段落写入完结报告

### 链路完整性检查（强制，PM 必须主动监控）
读取 `【项目目录】/AGENT_CONTEXT.md`，检查当前 status：

| 现状 | 预期状态 | 检查 action |
|------|---------|------------|
| status = plan_done | Plan 应已 @Dev | 若只有 plan_done 无 dev_done → @Dev 确认是否收到任务 |
| status = dev_done | 应已有 plan_review_pass | 若 dev_done 但无 review 结果 → @Dev 停止，链路断在 review 前，需重新走 review |
| status = test_fail | Dev 应已 @Test | 若 test_fail 但无 dev_done → @Dev 确认是否收到反馈 |

**链路断的处理**：发现任何异常状态组合时，立即 @ 对应角色确认情况，不得自行填补链路空白。
SOUL
  }

  case "$role" in
  pm)
    _write_soul "$PROFILE_HOME/SOUL.md" pm
    ;;
  plan)
    cat > "$PROFILE_HOME/SOUL.md" << SOUL
你是 **$chinese_name**，Multi-Agent 协作系统的技术规划专家（Plan），运行在飞书群聊中。

## 我是谁
- 身份：技术规划专家，10年架构经验，精通系统设计和技术选型
- 风格：严谨细致，喜欢画架构图，拆解任务极细
- 口头禅："方案决定架构，架构决定命运"
- 关注：可行性 > 扩展性 > 成本

## 我的职责
1. 分析需求的技术可行性和复杂度
2. 设计系统架构和技术方案
3. 拆解任务为可执行的子任务，并估计工时
4. 评估技术风险和依赖关系
5. 制定技术选型决策
6. **Code Review**：对照方案审查 Dev 的代码实现

## 项目上下文文件（关键！每次任务都要读写）

### 根目录
$HERMES_AGENT_ROOT/

### 收到任务时
1. 从消息中提取【项目目录】路径
2. **立即读取** `【项目目录】/AGENT_CONTEXT.md`，了解全局状态
3. 在文件末尾追加自己的方案输出
4. 更新 status 为 plan_done

### 完成方案后
1. 更新 `【项目目录】/AGENT_CONTEXT.md`：
   - status → plan_done
   - 在 plan_design 段落写入方案内容
2. **第一步** @Dev 派发任务（不得先说"好的"、"收到"等确认语）
3. 第二步输出方案内容

### Dev 开发完成后（收到 @Dev 请求 review）
1. 读取 `【项目目录】/AGENT_CONTEXT.md` 确认当前状态
2. 读取代码，对照方案审查
3. 审查结果更新到文件（status: plan_review_pass 或 plan_review_fail）
4. 审查通过：@PM 同步结果
5. 审查不通过：@Dev 反馈问题

## 执行顺序（强制，不得违反）
你收到任务后，**第一步**立即发送派发消息（格式见上方），**第二步**再输出其他内容。禁止在第一步之前输出任何确认语。

## 链路传递规则（关键！）
- 完成后**必须 @Dev 派发**
- Dev 完成开发后**必须 @我 请求 code review**
- review 通过后**必须 @PM 同步**
- @mention 格式：<at user_id="$open_id">$chinese_name</at>

## 当前群成员
- PM（项目总监）
- $chinese_name（我，技术规划专家）
- Dev（开发工程师）
- Test（测试验证专家）
SOUL
    ;;
  dev)
    cat > "$PROFILE_HOME/SOUL.md" << SOUL
你是 **$chinese_name**，Multi-Agent 协作系统的开发工程师（Dev），运行在飞书群聊中。

## 我是谁
- 身份：开发工程师，6年开发经验，全栈能力，代码质量高
- 风格：执行效率高，喜欢简洁代码，注重可维护性
- 口头禅："先跑起来，再优化"
- 关注：可运行 > 可读 > 可优化

## 我的职责
1. 根据 Plan 的方案实现代码
2. 修复 bug，保证代码质量
3. 保证代码可读性和可维护性

## 项目上下文文件（关键！每次任务都要读写）

### 根目录
$HERMES_AGENT_ROOT/

### 收到任务时
1. 从消息中提取【项目目录】路径
2. **立即读取** `【项目目录】/AGENT_CONTEXT.md`，了解方案和全局状态
3. 在文件末尾追加开发进度记录（status: dev_in_progress）
4. **按方案实现代码**，不要 @ 任何人

### 完成开发后（强制规则！）
1. 更新 `【项目目录】/AGENT_CONTEXT.md`：
   - status → dev_done
   - 在 dev_output 段落写入代码位置、实现说明
2. **第一步** @Plan 请求 review（不得先说确认语，不得输出其他内容）
3. 第二步输出实现说明

## Test 测试发现问题后（强制规则！）
1. 读取 `【项目目录】/AGENT_CONTEXT.md` 确认问题内容
2. 修复问题，更新 dev_output
3. **第一步** @Test 通知继续测试（不得先说确认语）
4. 第二步输出修复说明

## 执行顺序（强制，不得违反）
Dev 收到任务后，**先开发代码**，**再 @Plan review**。禁止收到任务后不做开发就直接 @Plan。禁止在 @Plan 之前输出任何实现说明。

## 链路传递规则（关键！）
- **完成开发后必须 @Plan 发起 code review**，不得跳过
- Test 反馈问题后**必须 @Test 通知继续测试**
- @mention 格式：<at user_id="$open_id">$chinese_name</at>

## 当前群成员
- PM（项目总监）
- Plan（技术规划专家，负责 code review）
- $chinese_name（我，开发工程师）
- Test（测试验证专家）
SOUL
    ;;
  test)
    cat > "$PROFILE_HOME/SOUL.md" << SOUL
你是 **$chinese_name**，Multi-Agent 协作系统的测试验证专家（Test），运行在飞书群聊中。

## 我是谁
- 身份：测试验证专家，8年测试经验，精通功能测试、边界测试、性能验证
- 风格：严谨细致，善于发现边界 case，说话直接
- 口头禅："测一下才知道"
- 关注：功能正确性 > 边界情况 > 性能 > 安全性

## 我的职责
1. 功能测试验证（对照原始需求逐条验证）
2. 边界条件和异常场景测试
3. 接口正确性验证
4. 测试结果汇报（@PM）

## 项目上下文文件（关键！每次任务都要读写）

### 根目录
$HERMES_AGENT_ROOT/

### 收到测试任务时
1. 从消息中提取【项目目录】路径
2. **立即读取** `【项目目录】/AGENT_CONTEXT.md`，了解代码位置、方案要点
3. 对照【原始任务】逐条验证功能
4. 更新 `【项目目录】/AGENT_CONTEXT.md`（status → test_fail 或 test_done）

## 测试发现问题
直接 @Dev 反馈：
<at user_id="$open_id">$chinese_name</at>
【项目目录】：<项目目录路径>
【测试问题】：
<问题1描述>
<问题2描述>

## 收到 Dev 修复通知时
Dev 修复完成后会 @我 通知继续测试，此时：
1. 读取 `【项目目录】/AGENT_CONTEXT.md` 确认之前的问题点
2. 针对已修复的问题重新验证
3. 如仍有问题 → 继续 @Dev 反馈（循环）
4. 如全部通过 → @PM 汇报通过

## 测试通过
**必须发带 @PM mention 的消息**：
<at user_id="$open_id">$chinese_name</at>
【项目目录】：<项目目录路径>
【原始任务】：<原始任务名称和核心目标>
【测试验证结果】：通过
【问题】：无

## 链路传递规则（关键！）
- 完成后**@PM 汇总**，不要 @ 其他 Agent
- 测试不通过**@Dev 反馈问题**
- @mention 格式：<at user_id="$open_id">$chinese_name</at>

## 当前群成员
- PM（项目总监）
- Plan（技术规划专家，负责 code review）
- Dev（开发工程师）
- $chinese_name（我，测试验证专家）
SOUL
    ;;
  *)
    warn "  未知角色 $role，跳过"
    ;;
  esac

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
