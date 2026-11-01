# Automations

Create scheduled and event-triggered automations in Tern. Each run gets its own session, so you can read its output or take it over.

The scheduler runs in the plugin's host half, inside Tern's session daemon. It keeps running while every window is closed, and only one instance runs however many windows are open. Tern stops an idle daemon (no windows and no running programs); while it is stopped nothing runs, and a missed slot starts within its grace period once the daemon is back.

## Install

```sh
tern plugin install github.com/msokh/tern-plugins/plugins/automations
```

## Create an automation

1. Open **Automations: Open** from the command palette.
2. Click **New automation**. Enter a name and choose **Command**, **OMP**, **Codex**, or **Claude**.
3. Enter the command or agent instructions. Add schedule or event triggers, or remove every trigger for manual execution only.
4. Choose an existing directory, an empty workspace, or a new git worktree for each run.
5. Click **Create automation**.

The manager supports editing, search, status filters, pause, and execution history. **Run now** skips the precheck, including for paused automations. **Pause** stops automatic runs.

Use Cmd+Z to undo text edits and Cmd+Shift+Z to redo them. Returning focus to a field starts a separate typing group.

**Automations: Show runs** opens execution history. **Automations: Run now** offers a picker without opening the manager.

A successful program closes its session. A nonzero exit keeps the session open. The manager records the program's exit, not just a successful launch.

The agent uses its existing CLI permissions and credentials. The plugin does not grant permissions or add approval-bypass flags. The selected CLI must be on Tern's `PATH`.

## Configuration reference

Definitions live in `~/.config/tern-automations/automations.json`. Keep instructions, private paths, and credentials outside this repository.

```json
{
  "automations": [
    {
      "id": "daily-review",
      "name": "Daily review",
      "agent": "codex",
      "instructions": "Review repository changes and report findings.",
      "workspace": "existing",
      "cwd": "~/example-project",
      "triggers": [
        { "kind": "schedule", "cron": "35 9 * * *" },
        {
          "kind": "event",
          "source": "webhook",
          "event": "repository.updated",
          "filter": "kind=review"
        }
      ],
      "grace_minutes": 60,
      "enabled": true
    }
  ]
}
```

| Field | Meaning |
|---|---|
| `id` | Immutable identifier containing lowercase letters, digits, and hyphens. The editor generates an unused identifier from the name. |
| `name` | Display name. Existing command definitions without a name display their identifier. |
| `agent` | `command`, `omp`, `codex`, or `claude`. Existing command definitions default to `command`. |
| `instructions` | Required for agents. The launcher passes instructions through a local file, not shell interpolation. |
| `model` | Optional agent model. An empty value uses the CLI default. |
| `command` | Program and argument array for `command`. No shell interprets the array unless you explicitly choose a shell. |
| `workspace` | `existing`, `none`, or `worktree`. `none` creates a scratch directory. `worktree` creates a detached git worktree. |
| `cwd` | Absolute or `~/` directory for `existing` and `worktree`. Omitted for `none`. |
| `base_branch` | Optional git revision for a new worktree. An empty value uses `HEAD`. |
| `triggers` | Schedule and event triggers. Any matching trigger starts a run. An empty array permits only manual runs. |
| `cron` | Existing command definitions can use this field instead of `triggers`. |
| `precheck` | Optional `{ "command": ["program", "argument"], "timeout_seconds": 60 }`. Automatic runs skip execution if the precheck fails or times out. |
| `grace_minutes` | Allowed delay for missed schedules and queued events, default 60. Only the newest missed schedule runs. |
| `enabled` | `false` stops automatic runs. Manual execution remains available. |

Cron uses five fields in local time: minute, hour, day of month, month, and day of week. Sunday is 0 or 7. Fields accept `*`, numbers, ranges, steps, and comma lists.

An event trigger has `kind`, `source`, `event`, and an optional `filter`. Supported sources are `github`, `webhook`, `slack`, and `linear`. Filters contain space-separated `key=value` terms. A value ending in `*` matches a prefix.

Event grace starts at the receiver's arrival timestamp. An event outside its grace period records a missed run instead of starting execution.

The scheduler rereads definitions every 15 seconds. Invalid entries appear as errors while valid entries continue to run. Saves retain unknown top-level and direct definition fields, including their nested values, and untouched invalid entries. An explicit definition edit rebuilds known trigger and precheck fields. Saves back up the previous file under `~/.local/state/tern-automations/backups/` and reject detected edit conflicts.

Run records and local prompt files live outside the plugin directory. The scheduler keeps 20 finished records per automation, plus unfinished or uncertain runs. It never removes git worktrees. After an interrupted launch, an uncertain outcome stays unknown rather than claiming success.

## Receive events

Choosing an event source does not subscribe to a provider. A separate trusted bridge must verify provider requests and deliver normalized events to the local receiver. The plugin does not install GitHub webhooks or subscribe to Slack or Linear.

Set `TERN_AUTOMATIONS_RECEIVER_TOKEN` in the receiver's environment to a random secret containing at least 16 characters. Do not store the secret in this repository or pass it as an argument.

In the plugin directory, run the receiver with Node.js 22 or later:

```sh
node receiver.mjs --port 47821
```

The receiver listens only on `127.0.0.1`. The bridge sends `POST /events` with `Content-Type: application/json` and `Authorization: Bearer <token>`. For the configuration above, the body is:

```json
{
  "id": "example-delivery-001",
  "source": "webhook",
  "event": "repository.updated",
  "attributes": { "kind": "review" },
  "payload": { "message": "Example update" }
}
```

The receiver rejects unauthorized requests before writing files. Requests are limited to 64 KiB, and the inbox is limited to 1,000 entries. Accepted deliveries return 202. Duplicate delivery identifiers return 200 without another enqueue, unless the inbox is full. A full inbox returns 503, including for duplicates. Delivery receipts expire after seven days.

The scheduler does not replay events received before its first connection. A triggered command receives the event file path in `TERN_AUTOMATION_EVENT`. Agent instructions include the normalized event. Persistent claims prevent normal replay, but interrupted operations do not guarantee exactly-once execution.

## Develop

```sh
tern plugin link plugins/automations
luau plugins/automations/tests/run.luau
luau plugins/automations/tests/ui.luau
node --test plugins/automations/tests/receiver.test.mjs
```

For disposable verification, set `TERN_AUTOMATIONS_HOME` before starting Tern and the receiver. Definitions use its `config/` directory, and runtime files use its `state/` directory. Also use a separate Tern configuration directory and daemon socket with `TERN_CONFIG_DIR` and `TERN_DAEMON_SOCKET`. The automation override alone does not isolate Tern's KV history, schedule cursors, or processed-event state.
