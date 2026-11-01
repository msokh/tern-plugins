# Tern plugins

Independent Tern plugins, one package per directory under `plugins/`, each with its own `plugin.toml`.

| Plugin | What it does |
|---|---|
| [automations](plugins/automations) | Creates scheduled and event-triggered agent runs in Tern sessions, with a native manager and execution history. |
| hello-alpha, hello-beta | Minimal examples: a palette command that shows a greeting. |

## Install

```sh
tern plugin install github.com/msokh/tern-plugins/plugins/<name>
```

To develop a plugin in place, run `tern plugin link /path/to/tern-plugins/plugins/<name>`.

## Keeping this repository public-safe

Nothing private belongs here: no personal or organization names, no absolute home paths, no secrets. Plugins read their real settings from files outside the repository.

`scripts/check-public.sh` enforces it. Enable the hooks once per clone:

```sh
git config core.hooksPath .githooks
```

The hooks check staged files and commit messages; CI checks the whole history. The list of names to reject lives outside the repository, in `~/.config/tern-plugins/denylist` locally (one name per line) and in the `TERN_PLUGINS_DENYLIST` Actions secret. The check fails without it. It needs `gitleaks` installed.
