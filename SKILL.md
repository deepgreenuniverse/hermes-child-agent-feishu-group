---
name: feishu-multi-agent-collaboration
description: Set up 2 or more Hermes agents as Feishu group bots collaborating via delegate_task. Send App ID + App Secret to the AI; it provisions profiles, SOUL.md, and launchd plists automatically. Roles are arbitrary — pick any naming and count.
triggers:
  - feishu multi-agent setup
  - hermes feishu bot team
  - PM Plan Dev chain feishu
---

# Feishu Multi-Agent Collaboration

## Background

Hermes Agent is a personal AI agent that can run multiple independent profiles, each with its own gateway, SOUL.md, and conversation context. Normally profiles live in separate Feishu (or other IM) groups for isolation.

When you need several agents to **collaborate inside one Feishu group** — e.g. PM dispatches a task to Plan, Plan writes a design for Dev, Dev writes code for Test, Test reports back to PM — you need N independent Feishu bots in the same group, each @mentioning the others by their real open_id.

This skill provisions that setup:
- Creates `~/.hermes/profiles/<role>/` for each role you specify
- Writes per-profile `config.yaml`, `SOUL.md`, `.env`
- Generates a shared `SOUL.md` template that knows every other role's open_id, so any agent in the group can @mention any other correctly
- Starts each profile's gateway (macOS launchd / Linux nohup)

You supply: N Feishu app credentials + chat_id. The AI does the rest.

## What you get

```
you → PM (Feishu) → Plan → Dev → Plan review → Test → PM report
              all via delegate_task; Feishu messages = external notifications
```

Default 4 roles (PM / Plan / Dev / Test) shown above — but you can have as few as 2 or as many as you want. Roles are not hardcoded: name them anything, count them however you like.

Default role table (most users start here, but you can name any roles you want):

| Role | Does | Doesn't |
|------|------|---------|
| PM  | receive requests, dispatch chain, report back | answer domain questions |
| Plan | architecture, plan output, code review | test, develop |
| Dev | implement per plan, fix bugs | design, test |
| Test | functional test, verify, report | review, develop |

Role keys in env vars (`ROLES=pm,plan,dev` etc.) must be **lower-case** to match `${role}_NAME` / `${role}_APP_ID` lookups in `setup.sh`. Two profiles is the minimum, ten is fine — there's no upper bound beyond how many Feishu apps you can create.

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

If running setup.sh yourself, set **lower-case** env vars (role key matches `ROLES`):

```bash
export ROLES="pm,plan,dev"
export pm_NAME="PM"     pm_APP_ID="cli_xxx"     pm_APP_SECRET="xxx"
export plan_NAME="Plan" plan_APP_ID="cli_xxx"    plan_APP_SECRET="xxx"
export dev_NAME="Dev"   dev_APP_ID="cli_xxx"     dev_APP_SECRET="xxx"
export FEISHU_CHAT_ID="oc_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
bash scripts/setup.sh
```

Or paste credentials to the AI and let it run setup.sh:

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

## Pre-flight checklist

Run these BEFORE running `setup.sh`. Any unchecked box = expected failure later.

**Feishu apps (per role):**
- [ ] All N apps have ≥1 published version (`open.feishu.cn` → app → 版本管理与发布)
- [ ] Bot capability enabled (应用能力 → 机器人)
- [ ] Required scopes: `im:message`, `im:message.group_at_msg`, `im:message:send_as_bot`

**Group:**
- [ ] Group exists, all N bots added (群设置 → 群机器人)
- [ ] Group `chat_id` copied (Settings → Group info)

**Hermes Agent config (`~/.hermes/config.yaml`):**
- [ ] `model:` block is full — has `api_key`, `api_mode`, `base_url`, `default`, `provider`, `context_length` (run `hermes config show` to verify)
- [ ] Env var follows `<PROVIDER>_API_KEY` convention: `provider=minimax-cn` → `MINIMAX_CN_API_KEY=…` in `~/.hermes/.env`

**Linux hosts running `hermes-gateway.service`:**
- [ ] Decide before setup: stop systemd service (custom profiles only) OR leave it active (it will spawn a default gateway that competes for the same Feishu app_id, causing `app_lock` conflicts)
  ```bash
  systemctl status hermes-gateway   # check active state
  ```

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

## Failure modes — log pattern → grep → fix

When a bot doesn't respond, scan logs in this order:

| Symptom (in `profiles/<role>/logs/gateway.log`) | Grep | Fix |
|---|---|---|
| `Unauthorized user: ou_XXX` | `grep -h "Unauthorized" ~/.hermes/profiles/*/logs/gateway.log \| tail -20` | Single trusted user: add `FEISHU_ALLOWED_USERS=ou_XXX` to that profile's `.env`. Multi-bot: add `FEISHU_ALLOW_ALL_USERS=true` to **all** profile `.env` files, restart. |
| `No LLM provider configured` or `provider: None` | `grep -h "No LLM provider\|provider.*None" ~/.hermes/profiles/*/logs/gateway.log` | Each profile's `config.yaml::model:` block is incomplete. Copy the full block from main config: `hermes config show \| grep -A 10 "^model:"`. `setup.sh` does this automatically — re-run it. |
| Bot @s another bot, recipient gateway shows `Inbound group message received` then `Unauthorized` | `grep -B1 "Unauthorized" ~/.hermes/profiles/<recipient>/logs/gateway.log` | Second-layer auth check. `FEISHU_GROUP_POLICY=open` only opens the first layer; set `FEISHU_ALLOW_ALL_USERS=true` in all profiles. |
| Short 200-char response that looks generic | `grep -h "RuntimeError" ~/.hermes/profiles/*/logs/gateway.log` | This is the gateway's fallback text, NOT the LLM's reply. Root cause is above (provider/model misconfigured). |
| `app_id or app_secret is invalid` | `grep -h "invalid" ~/.hermes/profiles/*/logs/gateway.log` | Wrong credentials, OR another gateway holds the lock. Check `~/.local/state/hermes/gateway-locks/` and remove stale entries. |

**Always run `hermes config check && hermes config show && hermes status` BEFORE reading logs** — most failures are config-not-runtime.

## Single-bot Feishu setup (default profile only)

Skip the chain — just wire `default` profile to Feishu:

```bash
grep FEISHU_APP_ID ~/.hermes/.env
grep FEISHU_BOT_OPEN_ID ~/.hermes/.env   # open_id is the #1 cause of @ not working
hermes gateway list
```

If all three return values but the bot doesn't respond, run through the @mention checklist above — same root causes apply.

## Stop / rollback

**macOS** (launchd):
```bash
for f in ~/Library/LaunchAgents/ai.hermes.gateway*.plist; do
  launchctl unload "$f" 2>/dev/null
done
ps aux | grep 'hermes_cli.main.*gateway' | grep -v grep | awk '{print $2}' | xargs kill -9 2>/dev/null
rm -f ~/.local/state/hermes/gateway-locks/*
```

**Linux** (nohup / systemd):
```bash
pkill -9 -f 'hermes_cli.main.*gateway' 2>/dev/null
sudo systemctl stop hermes-gateway 2>/dev/null   # if you started via install.sh
rm -f ~/.local/state/hermes/gateway-locks/*
```

**Full rollback** (delete all profiles):
```bash
pkill -9 -f 'hermes_cli.main.*gateway' 2>/dev/null
for p in pm-agent plan-agent dev-agent test-agent; do
  hermes profile delete "$p" -y 2>/dev/null
done
rm -rf ~/.hermes/profiles/{pm,plan,dev,test}-agent
# Edit ~/.hermes/config.yaml to remove FEISHU_* config if you added any
```

Verify clean: `ps aux | grep gateway | grep -v grep` returns nothing.

## Restart a gateway

`hermes gateway restart` is not supported.

**macOS** (launchd):
```bash
launchctl bootout gui/$(id -u)/ai.hermes.gateway-<profile> 2>&1
sleep 2
launchctl load ~/Library/LaunchAgents/ai.hermes.gateway-<profile>.plist
```

**Linux** (manual or systemd):
```bash
pkill -9 -f 'hermes_cli.main.*gateway.*<profile>' 2>/dev/null
sleep 2
nohup ~/.hermes/hermes-agent/venv/bin/python -m hermes_cli.main \
  gateway run --profile <profile> --replace \
  > ~/.hermes/profiles/<profile>/logs/gateway.log 2>&1 &
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
- `scripts/setup.sh` — bulk profile creation; cross-platform (macOS launchd + Linux nohup/systemd)
- `scripts/feishu-multi-agent-setup.py` — OAuth device-flow helper (auto-fetches credentials)