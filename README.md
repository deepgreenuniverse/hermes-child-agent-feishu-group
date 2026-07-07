# hermes-child-agent-feishu-group

通过 Hermes Agent 子 agent 搭建飞书群聊机器人团队的 skill。AI 自动完成 profile 创建、SOUL.md 生成、launchd plist 安装 —— 你只需在飞书开放台创建应用并粘贴凭证。

```
你 → PM（飞书）→ Plan → Dev → Plan 评审 → Test → PM 汇报
              全部走 delegate_task；飞书消息 = 外部通知
```

## 前置要求

- macOS（使用 launchd）
- [Hermes Agent](https://hermes-agent.nousresearch.com) 已安装到 `~/.hermes/`
- 每个飞书应用发布版本并开启机器人能力

## 前置检查（必跑，缺一项就报错）

- [ ] N 个飞书应用都已发版（[open.feishu.cn/app](https://open.feishu.cn/app) → 版本管理与发布）
- [ ] 每个应用开启机器人能力、授权 `im:message` / `im:message.group_at_msg` / `im:message:send_as_bot` 三个 scope
- [ ] N 个机器人全部加进目标群
- [ ] 主 profile 的 `~/.hermes/config.yaml::model:` 块完整（`api_key` / `api_mode` / `base_url` / `default` / `provider` / `context_length` 都得有；跑 `hermes config show` 验证）
- [ ] env var 命名遵循 `<PROVIDER>_API_KEY`：`provider=minimax-cn` → env 里写 `MINIMAX_CN_API_KEY`
- [ ] Linux 主机若 `hermes-gateway.service` 在跑，先决定：停 systemd（只用 custom profiles）还是留着（会和自定义 profile 抢同一个 Feishu app_id lock）

## 快速开始

1. 在 [open.feishu.cn/app](https://open.feishu.cn/app) 创建 N 个企业自建应用，开启机器人能力，发布版本
2. 创建一个群聊，把 N 个机器人全部拉进群
3. 把凭证发给 AI：

   自己跑 setup.sh 时设小写 env var（角色名跟 ROLES 一致）：
   ```bash
   export ROLES="pm,plan,dev"
   export pm_NAME="PM"     pm_APP_ID="cli_xxx"     pm_APP_SECRET="xxx"
   export plan_NAME="Plan" plan_APP_ID="cli_xxx"    plan_APP_SECRET="xxx"
   export dev_NAME="Dev"   dev_APP_ID="cli_xxx"     dev_APP_SECRET="xxx"
   export FEISHU_CHAT_ID="oc_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
   bash scripts/setup.sh
   ```

   或者把凭证发给 AI 让它跑：
   ```
   飞书群 chat_id：oc_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

   PM：  app_id cli_xxx，app_secret xxx
   Dev： app_id cli_xxx，app_secret xxx
   ```

4. AI 自动完成所有配置（profiles、SOUL.md、launchd plist、启动 gateway）

## 批量创建飞书应用（可选）

如果不想在飞书开放台手动创建 N 个应用，启动本地工具一次性批量创建：

```bash
cd scripts/
python3 feishu-multi-agent-setup.py
# 浏览器打开 http://127.0.0.1:8765
```

按页面提示逐个扫码授权即可。完成后所有 app_id + app_secret 会显示在结果区，直接复制粘贴给 AI。

> 此工具调用飞书 OAuth Device Flow 创建 PersonalAgent 类型应用，需要飞书账号具备创建权限。

完整文档：[`SKILL.md`](SKILL.md)

> [English version](README_EN.md)

## 许可证

MIT。详见 [LICENSE](LICENSE)。