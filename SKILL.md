---
name: feishu-multi-agent-collaboration
description: Set up 2-5 Hermes agents as Feishu group bots collaborating via delegate_task. Send App ID + App Secret to the AI; it provisions profiles, SOUL.md, and launchd plists automatically.
triggers:
  - feishu multi-agent setup
  - hermes feishu bot team
  - PM Plan Dev chain feishu
---

# Feishu Multi-Agent Collaboration

Deploy 2-5 Hermes agents as a Feishu group bot team. The AI handles all provisioning — you only create the Feishu apps and paste credentials.

## What you get

```
you → PM (Feishu) → Plan → Dev → Plan review → Test → PM report
              all via delegate_task; Feishu messages = external notifications
```

Roles are flexible. Default 4:

| Role | Does | Doesn't |
|------|------|---------|
| PM  | receive requests, dispatch chain, report back | answer domain questions |
| Plan | architecture, plan output, code review | test, develop |
| Dev | implement per plan, fix bugs | design, test |
| Test | functional test, verify, report | review, develop |

Or 2-5 of anything (`pm,dev` minimum; rename freely).

## Setup (5 minutes)

### 1. Create Feishu apps

For each agent (N = number of bots you want):
1. Go to [open.feishu.cn/app](https://open.feishu.cn/app) → Create enterprise app
2. App capabilities → Bot → Enable
3. Version management → Create version → Publish (required, bot won't respond to @ until published)
4. Copy App ID + App Secret

### 2. Create the group, add bots

1. Create a Feishu group chat
2. Add all N bots to the group (Settings → Group bots → Add)
3. Copy the group chat_id (Settings → Group info → at the bottom)

### 3. Paste credentials to AI

```
Feishu group chat_id: oc_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

PM:     app_id cli_xxx, app_secret xxx
Plan:   app_id cli_xxx, app_secret xxx
Dev:    app_id cli_xxx, app_secret xxx
```

The AI will:
- Fetch each bot's `open_id` from `/bot/v3/info` (no need to ask you)
- Create `~/.hermes/profiles/<role>/` with config, SOUL.md, .env
- Install launchd plists, start all gateways

LLM config inherits from main Hermes agent; override per role if needed.

## Required checks before asking "why doesn't it work?"

```bash
# Are credentials present?
grep -E 'FEISHU_APP_ID|FEISHU_APP_SECRET|FEISHU_BOT_OPEN_ID' ~/.hermes/profiles/<role>/.env

# Is the gateway running?
hermes gateway list

# Is the group chat_id correct?
grep home_channel ~/.hermes/profiles/<role>/config.yaml
```

## @mention not working — check in this order

1. **App published** — bot won't respond to @ until version is published.
2. **`FEISHU_BOT_OPEN_ID` missing in `.env`** — the bot doesn't know its own open_id, can't route @s back to itself. Highest-priority failure.
3. **`channel_directory.json::feishu` array empty** — bot was never added to the group, gateway can't see it. Add bot to group, restart gateway.
4. **`FEISHU_ALLOW_BOTS` ≠ `all`** — bot-to-bot messages silently dropped at default `"none"`. Set in `config.yaml` or env.
5. **`FEISHU_ALLOWED_USERS` doesn't include sender** — message silently dropped. Add sender's open_id.
6. **SOUL.md missing @mention XML for other bots** — when you @Claude/@Codex in the group, the receiving bot doesn't know what to do. SOUL.md must contain:
   ```
   <at user_id="ou_xxx">Claude</at>
   <at user_id="ou_yyy">Codex</at>
   ```
   Plain `@name` text does NOT trigger anything in Feishu; XML only.
7. **Bot rebuilt on Feishu side → open_id changed** — update `FEISHU_BOT_OPEN_ID` in `.env` and every `<at user_id=>` in every SOUL.md. (Real open_id: grep gateway.log for `sender=bot:ou_xxx`.)

If multiple bots in one group, **each** must set `FEISHU_REQUIRE_MENTION=true` in their `.env`, or every bot answers every message.

## 3 files to inspect when a sub-agent behaves wrong

```bash
head -1 ~/.hermes/profiles/<role>/SOUL.md       # should be the role's identity, not another role's
grep chat_id ~/.hermes/profiles/<role>/config.yaml
grep oc_ ~/.hermes/profiles/<role>/channel_directory.json
```

All three must reference the same group.

## Single-bot Feishu setup (default profile only)

Skip the chain — just wire `default` profile to Feishu:

```bash
grep FEISHU_APP_ID ~/.hermes/.env
grep FEISHU_BOT_OPEN_ID ~/.hermes/.env   # open_id is the #1 cause of @ not working
hermes gateway list
```

If all three return values but the bot doesn't respond, run through the @mention checklist above — same root causes apply.

## Stop everything

```bash
for f in ~/Library/LaunchAgents/ai.hermes.gateway*.plist; do
  launchctl unload "$f" 2>/dev/null
done
ps aux | grep 'hermes_cli.main.*gateway' | grep -v grep | awk '{print $2}' | xargs kill -9 2>/dev/null
rm -f ~/.local/state/hermes/gateway-locks/*
```

Verify clean: `ps aux | grep gateway | grep -v grep` returns nothing.

## Restart a gateway

`hermes gateway restart` is not supported. Use launchd:

```bash
launchctl bootout gui/$(id -u)/ai.hermes.gateway-<profile> 2>&1
sleep 2
launchctl load ~/Library/LaunchAgents/ai.hermes.gateway-<profile>.plist
```

## Get a bot's open_id (when you need it manually)

```bash
TOKEN=$(curl -s -X POST 'https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal' \
  -H 'Content-Type: application/json' \
  -d '{"app_id":"<APP_ID>","app_secret":"<APP_SECRET>"}' | python3 -c "import sys,json; print(json.load(sys.stdin)['tenant_access_token'])")
curl -s -X GET 'https://open.feishu.cn/open-apis/bot/v3/info' -H "Authorization: Bearer $TOKEN"
# → {"bot":{"open_id":"ou_xxx",...}}
```

## Multi-bot @ mention XML format

Feishu bot must emit and parse ONLY XML, never plain text:

```xml
<at user_id="ou_xxx_bot_a">BotA</at> please review
```

Text form `@BotA please review` does nothing. SOUL.md prompt blocks, message construction, and reference docs all use XML.

## Chain discipline

| Rule | If broken |
|------|-----------|
| Chain dispatch uses `delegate_task`, not Feishu messages | "ok" response ≠ delivered; task silently lost |
| Dev only @Plan review AFTER code is committed | review on empty diff, chain stalls |
| Every bot's first message must @downstream | handoff fails silently |
| Adding a new bot → update SOUL.md of ALL existing bots | existing bots can't @ new bot |
| Don't run launchd + manual gateway at the same time | port collision, duplicate tokens |

## Prerequisites

macOS. Hermes Agent installed. Each Feishu app published with bot capability enabled.

## Files

- `SKILL.md` — this file
- `scripts/setup.sh` — bulk profile creation + launchd plist install
- `scripts/feishu-multi-agent-setup.py` — OAuth device-flow helper (auto-fetches credentials)