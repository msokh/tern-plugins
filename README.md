# Tern plugins

Two small example plugins for checking that Tern can install independent packages from one repository.

## Install

```sh
tern plugin install github.com/msokh/tern-plugins/plugins/hello-alpha
tern plugin install github.com/msokh/tern-plugins/plugins/hello-beta
```

Open the Tern command palette and run **Hello Alpha** or **Hello Beta**. Each command displays its own greeting.

Each directory under `plugins/` is a separate package with its own `plugin.toml`. To develop a plugin in place, run `tern plugin link /path/to/tern-plugins/plugins/hello-alpha`.
