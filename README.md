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

## 快速开始

1. 在 [open.feishu.cn/app](https://open.feishu.cn/app) 创建 N 个企业自建应用，开启机器人能力，发布版本
2. 创建一个群聊，把 N 个机器人全部拉进群
3. 把凭证发给 AI：

   ```
   飞书群 chat_id：oc_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

   PM：  app_id cli_xxx，app_secret xxx
   Dev： app_id cli_xxx，app_secret xxx
   ```

4. AI 自动完成所有配置（profiles、SOUL.md、launchd plist、启动 gateway）

完整文档：[`SKILL.md`](SKILL.md)

> [English version](README_EN.md)

## 许可证

MIT。详见 [LICENSE](LICENSE)。