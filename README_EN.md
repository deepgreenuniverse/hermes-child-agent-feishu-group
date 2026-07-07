# hermes-child-agent-feishu-group

Deploy 2-5 [Hermes Agent](https://hermes-agent.nousresearch.com) profiles as a Feishu bot team. The AI handles profile creation, SOUL.md generation, and launchd plist install — you only create the Feishu apps and paste credentials.

```
you → PM (Feishu) → Plan → Dev → Plan review → Test → PM report
              all via delegate_task; Feishu messages = external notifications
```

> [中文版](README.md)

## Requirements

- macOS (uses launchd)
- [Hermes Agent](https://hermes-agent.nousresearch.com) installed at `~/.hermes/`
- Each Feishu app published with bot capability enabled

## Quickstart

1. Create N Feishu apps at [open.feishu.cn/app](https://open.feishu.cn/app); enable bot, publish.
2. Create a group chat, add all N bots.
3. Paste credentials to the AI:

   ```
   Feishu group chat_id: oc_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

   PM:   app_id cli_xxx, app_secret xxx
   Dev:  app_id cli_xxx, app_secret xxx
   ```

4. The AI provisions everything (profiles, SOUL.md, launchd plists, gateways).

Full docs: [`SKILL.md`](SKILL.md)

## License

MIT. See [LICENSE](LICENSE).