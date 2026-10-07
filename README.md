# Plugin probe for Omarchy

The shell gets slow or bloated and nobody can tell which plugin did it. Plugin
probe puts the shell's memory in the bar and ranks plugins by what they cost:
helper processes, their memory and CPU. For the part a process list can't
show (QML running inside the shell itself), `probe ablate` measures the shell
with and without a plugin and tells you whether the difference is bigger than
the noise.

## Install

```sh
omarchy plugin add https://github.com/Nejcc/omarchy-plugin-probe.git
omarchy plugin enable nejcc.plugin-probe
```

## Usage

- **Bar:** an icon and the shell's RSS. Hover for the shell's CPU and the
  heaviest helper. Click for the panel, middle click to refresh.
- **Panel:** every plugin that runs a helper process, heaviest first, with
  process count, RSS and CPU. Processes the shell started that no plugin
  claims are listed as "other shell children".
- **CLI**, from the plugin folder (`~/.config/omarchy/plugins/nejcc.plugin-probe`):

```sh
bin/probe snapshot            # table
bin/probe snapshot --json     # what the widget reads
bin/probe ablate <plugin-id>  # with/without comparison, see below
```

### Ablate

```sh
bin/probe ablate omarchy.weather --runs 3 --settle 15
```

It restarts your shell `2 × runs + 1` times, so it asks first (`--yes` skips
the question). Each run swaps in your `shell.json` with the plugin on or off,
runs `omarchy-restart-shell`, waits for `omarchy-shell shell ping`, lets the
shell settle, then records shell RSS, the plugin's helper RSS and startup time
(process start to first ping). Runs alternate with/without so slow drift lands
on both sides. The report shows the mean and min-max per side, the delta, and
"above noise" only when the delta is bigger than the spread of either side.

Your `shell.json` is copied before anything changes and copied back at the
end, also on Ctrl+C or a failed restart, then the shell is restarted once
more. A file copy, not a re-enable, because disabling a bar widget removes it
from the layout and enabling it again would not put it back where it was.

The widget never runs ablate.

## How it works

`bin/probe snapshot` reads `/proc` twice, a second apart. A process belongs to
a plugin when its command line mentions the plugin's folder
(`~/.config/omarchy/plugins/<id>` or `$OMARCHY_PATH/shell/plugins/...`) or its
working directory is inside it. Its descendants belong to the same plugin, so
a helper's children count too. The shell is the `quickshell -p
$OMARCHY_PATH/shell` process. Enabled state comes from `omarchy-shell shell
listPlugins`. The attribution lives in `bin/attribute.jq`.

The widget runs a snapshot every 5 minutes, every 10 seconds while the panel is open.
One snapshot costs about half a second of CPU.

## Runtime dependencies

`bash`, `jq`, GNU `find`, `column`. All on a stock Omarchy install.

## Limits

- Plugin QML runs inside the shell, so its memory shows up as shell RSS, not
  under the plugin. Only `ablate` gets at it, and only as a difference between
  two restarts.
- A helper that never mentions its plugin folder (a bare `udevadm monitor`,
  say) can't be told apart and lands in "other shell children".
- A helper that hands work to an existing daemon (D-Bus, systemd) doesn't
  carry that daemon's cost.
- Long-running helpers that reparent away from the shell are still found by
  their command line; their children are counted, which for something like a
  tmux server includes the shells you run in it.
- Startup time stops at the first ping. Plugins that finish loading later
  show up in settled RSS, not in startup.
- No wakeup counts yet.

## Tests

```sh
bash tests/probe.test.sh
```

Runs the probe against a fake `/proc` tree, and `ablate` against a fake shell,
so nothing on your desktop is touched.

## License

MIT
