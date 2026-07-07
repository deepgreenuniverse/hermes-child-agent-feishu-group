# hermes-child-agent-feishu-group

Deploy 2-5 [Hermes Agent](https://hermes-agent.nousresearch.com) profiles as a Feishu bot team. The AI handles profile creation, SOUL.md generation, and launchd plist install — you only create the Feishu apps and paste credentials.

```
you → PM (Feishu) → Plan → Dev → Plan review → Test → PM report
              all via delegate_task; Feishu messages = external notifications
```

> [中文版](README.md)

## Requirements

- macOS (uses launchd) OR Linux (nohup / systemd)
- [Hermes Agent](https://hermes-agent.nousresearch.com) installed at `~/.hermes/`
- Each Feishu app published with bot capability enabled

## Pre-flight checklist

Run these BEFORE running setup.sh. Each box unchecked = expected failure later.

- [ ] All N apps have ≥1 published version ([open.feishu.cn/app](https://open.feishu.cn/app) → 版本管理与发布)
- [ ] Bot capability enabled on each app, with scopes: `im:message`, `im:message.group_at_msg`, `im:message:send_as_bot`
- [ ] All N bots added to the target group
- [ ] Main profile's `~/.hermes/config.yaml::model:` block is full — has `api_key`, `api_mode`, `base_url`, `default`, `provider`, `context_length` (verify with `hermes config show`)
- [ ] Env var naming follows `<PROVIDER>_API_KEY`: `provider=minimax-cn` → `MINIMAX_CN_API_KEY` in `~/.hermes/.env`
- [ ] Linux hosts: if `hermes-gateway.service` is active, decide before setup — stop systemd (custom profiles only) or leave it (will conflict on the same Feishu app_id lock)

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

## Batch-create Feishu apps (optional)

If you'd rather skip manual app creation in Feishu's console, the bundled tool creates N apps via OAuth Device Flow:

```bash
cd scripts/
python3 feishu-multi-agent-setup.py
# Open http://127.0.0.1:8765 in your browser
```

Scan the QR codes on screen — once done, all `app_id` + `app_secret` pairs appear in the results panel, ready to paste to the AI.

> Requires a Feishu account with permission to create PersonalAgent-type apps.

Full docs: [`SKILL.md`](SKILL.md)

## License

MIT. See [LICENSE](LICENSE).