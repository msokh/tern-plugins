# Tern plugins

Independent Tern plugins, one package per directory under `plugins/`, each with its own `plugin.toml`.

| Plugin | What it does |
|---|---|
| [automations](plugins/automations) | Creates scheduled and event-triggered agent runs in Tern sessions, with a native manager and execution history. |
| [ui-gallery](plugins/ui-gallery) | Renders every native UI builder Tern gives plugins, to check a plugin's UI against Tern's own blocks. |
| hello-alpha, hello-beta | Minimal examples: a palette command that shows a greeting. |

## Install

```sh
tern plugin install github.com/msokh/tern-plugins/plugins/<name>
```

To develop a plugin in place, run `tern plugin link /path/to/tern-plugins/plugins/<name>`.

## Building UI

A plugin's UI should be indistinguishable from Tern's built-in blocks. Build it from Tern's own builders (`tern.ui.button`, `table`, `card`, `badge`, `kv` and the rest), the same ones the built-in blocks use. When none covers a need, add a Component to `lib/ui/`, assembled from those builders.

Tern loads each package on its own, and a plugin cannot `require` a file outside its directory. So `lib/ui/` is copied into every plugin that requires `./ui/...`:

```sh
node scripts/ui.mjs sync    # copy lib/ui into plugins/<name>/ui
node scripts/ui.mjs check   # fail on a stale copy, a raw ui.el, a restyled .sf-* class, or cursor/height/padding in plugin CSS
```

Never edit `plugins/<name>/ui/` by hand. `scripts/preview.mjs <name>` renders a plugin's screens in the running Tern window from fixtures in `scripts/preview/<name>/` and saves a PNG per screen.

## Keeping this repository public-safe

Nothing private belongs here: no personal or organization names, no absolute home paths, no secrets. Plugins read their real settings from files outside the repository.

`scripts/check-public.sh` enforces it. Enable the hooks once per clone:

```sh
git config core.hooksPath .githooks
```

The hooks check staged files and commit messages; CI checks the whole history. The list of names to reject lives outside the repository, in `~/.config/tern-plugins/denylist` locally (one name per line) and in the `TERN_PLUGINS_DENYLIST` Actions secret. The check fails without it. It needs `gitleaks` installed.
