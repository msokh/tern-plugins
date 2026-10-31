# Automations

Starts agents on a cron schedule. Each run gets its own Tern session, so you can watch it, read what it printed, or take it over.

The scheduler runs in the plugin's host half, inside Tern's session daemon. It keeps running while every window is closed, and only one instance runs however many windows are open. Tern stops an idle daemon (no windows and no running programs); while it is stopped nothing runs, and a missed slot starts within its grace period once the daemon is back.

## Install

```sh
tern plugin install github.com/msokh/tern-plugins/plugins/automations
```

## Configure

Automations are defined outside the plugin, in `~/.config/tern-automations/automations.json`. Keep prompts, paths and anything private there or in the files it points to, never in this repository.

```json
{
  "automations": [
    {
      "id": "daily-review",
      "cron": "35 9 * * *",
      "cwd": "~/automations/daily-review",
      "command": ["omp", "-p", "@prompt.md"],
      "precheck": { "command": ["~/automations/daily-review/precheck.sh"], "timeout_seconds": 120 },
      "grace_minutes": 720,
      "enabled": true
    }
  ]
}
```

| Field | Meaning |
|---|---|
| `id` | Lowercase letters, digits and `-`. Names the runs' sessions: `auto-<id>-<YYYYMMDDHHMM>`. |
| `cron` | Five fields, local time: minute, hour, day of month, month, day of week (0 or 7 is Sunday). Each takes `*`, `N`, `A-B`, `/STEP` and comma lists. |
| `cwd` | Absolute or `~/` path the run starts in. |
| `command` | The program and its arguments, run as given. `~/` expands; relative paths resolve against `cwd`. |
| `precheck` | Optional. Runs before each scheduled run, in `cwd`; give the program by name on `PATH`, or as an absolute or `~/` path. Any exit other than 0, or passing `timeout_seconds` (default 60), skips the run. |
| `grace_minutes` | How late a slot may still start, after sleep or a stopped daemon (default 60). Only the newest missed slot runs. |
| `enabled` | `false` stops scheduled runs; Run now still works (default `true`). |

The file is read again every 15 seconds. An invalid entry is reported and skipped; the others keep running.

A run whose command exits 0 closes its session. Any other exit keeps the session open to read.

## Use

From the command palette:

- **Automations: Run now** starts one immediately, without its precheck.
- **Automations: Show status** opens `~/.local/state/tern-automations/status.md`: config problems and the last five runs of each automation, with their outcome (`exited 0`, `skipped_precheck`, `launch_failed`, …).

## Develop

```sh
tern plugin link plugins/automations
luau plugins/automations/tests/run.luau
```
