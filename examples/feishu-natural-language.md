# Natural language phrases for Feishu DM

Phrases tested in production with a Chinese chat agent. Chinese preferred
because the user is Chinese-speaking. Add English variants if your
audience is mixed.

## on (turn proxy on)

Works:

- `开代理`
- `帮我开代理`
- `flclash 开`
- `flclash on`
- `启动代理`
- `代理开`
- `上代理`
- `挂代理`
- `enable proxy`
- `proxy on`

Avoid:

- `/flclash on` — Hermes intercepts `/...` prefix
- `请把 FlClash 启动一下` — too verbose, no agent
- `我要访问 x.com` — implies proxy, but agent might not know to turn it on

## off (turn proxy off)

- `关代理`
- `帮我关代理`
- `flclash 关`
- `flclash off`
- `关掉代理`
- `代理关`
- `下代理`
- `卸代理`
- `disable proxy`
- `proxy off`

## status

- `代理状态`
- `看看代理`
- `看看代理开没开`
- `代理什么情况`
- `flclash 状态`
- `flclash status`
- `proxy status`

## How the agent maps phrases to actions

The agent's `SKILL.md` description (the `description:` YAML frontmatter) is
loaded by the chat platform. When a user message contains words like
"代理", "flclash", "proxy" combined with action verbs ("开", "关", "状态",
"on", "off", "status"), the platform passes the message to the skill, which
runs the script.

If the platform uses intent classification, the natural language is parsed
and routed. If it's rule-based, list the phrases explicitly in the skill's
description.
