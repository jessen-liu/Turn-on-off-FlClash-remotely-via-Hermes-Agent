# Hermes config snippet

If you use [Hermes](https://github.com) as your chat agent, drop the skill into
`~/.hermes/skills/flclash-toggle/` and Hermes will auto-discover it.

The natural-language phrases you should send in Feishu DM (or Telegram, etc.):

| Phrase | Action |
|---|---|
| `开代理` / `帮我开代理` / `flclash 开` | turn proxy on |
| `关代理` / `帮我关代理` / `flclash 关` | turn proxy off |
| `代理状态` / `看看代理开没开` / `flclash 状态` | print current state |

Hermes invokes the script via:
```cmd
"%USERPROFILE%\.hermes\skills\flclash-toggle\scripts\flclash.bat" on
```

The wrapper locates `pwsh.exe` automatically. Output is pasted back to the chat
verbatim.

## Hermes `~/.hermes/config.yaml` snippet

No changes required to `config.yaml`. The skill lives entirely in `skills/`.

## Important: avoid `/flclash` prefix

Do **not** use `/flclash on` style. Hermes (and most chat agent platforms)
treat any `/...` prefix as a platform command. `/flclash` is not a registered
platform command, so it returns "Unknown command /flclash" and the user
message never reaches the skill. Use plain natural language instead.
