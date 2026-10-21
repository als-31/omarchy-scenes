# Scenes

Save your whole desktop as a **scene** and bring it back with one key.

Hyprland has no session restore. Every reboot, and every `omarchy update`
that wants one, you rebuild the same layout by hand: the editor in the project
on 1, the browser on 2, chat on 3. Scenes does that for you.

![Scenes picker](preview.png)

## What a scene remembers

- **Every window**, on its workspace and monitor, in tiling order, or floating
  exactly where it was (special workspaces such as the scratchpad included)
- **Terminals** reopen in their working directory and rerun what was running
  in them: `nvim`, `lazygit`, `btop`, `claude`, `yazi` and
  [friends](#settings)
- **Web apps and PWAs** come back at their address, matched to your Omarchy
  web app launchers
- **Apps** start from their desktop entry, the same way the app launcher
  starts them

Restoring is idempotent. A window that is already open is moved into place
instead of being opened twice, so you can restore a scene over a half-built
desktop and only the missing windows appear. New windows open straight onto
their workspace with a temporary Hyprland rule, so nothing flashes across
the screen you're looking at.

**Previous session:** Scenes keeps a rolling snapshot of your desktop. After
you log in again, the desktop you had before shows up as *Previous session*.
One Enter puts it all back.

## Install

```bash
omarchy plugin add https://github.com/saidrmdhani/omarchy-scenes.git --enable
```

The Scenes button lands in the right side of the bar. Move it with
`omarchy bar move saidness.scenes --section left`.

Then add keybindings to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + CTRL + ALT + S", "Scenes", "omarchy-shell shell toggle saidness.scenes '{}'")
o.bind("SUPER + CTRL + SHIFT + S", "Save scene", "omarchy-shell shell summon saidness.scenes '{\"mode\":\"save\"}'")
```

## Using it

Open the picker with `Super + Ctrl + Alt + S` or by clicking the Scenes icon.
Click the active scene's name to restore it immediately.

| Key | In the picker |
| --- | --- |
| type | filter scenes by name, app or folder |
| `Enter` | restore the selected scene |
| `Ctrl S` | save the current layout as a new scene |
| `Ctrl R` / `F2` | rename |
| `Ctrl O` | update the scene with the windows open right now |
| `Del` | delete |
| `Esc` | clear the filter, then close |

While naming a scene, `Tab` takes the suggested name: the project most of
your terminals are in.

The bar button shows the active scene, and restore progress while one comes
back. Right click either the icon or scene name to save the current layout.
Turn the name off in the widget's settings (`showName`) if you want just the
icon.

## Command line

Everything runs on a small engine that also works on its own, so hooks,
scripts and keybindings can use it directly:

```bash
scenes=~/.config/omarchy/plugins/saidness.scenes/bin/scenes

$scenes save "Client work"        # snapshot every open window
$scenes restore "Client work"     # bring it back
$scenes restore previous          # the desktop before your last login
$scenes list
$scenes rename "Client work" "Acme"
$scenes delete "Acme"
$scenes capture | jq              # the current desktop as scene JSON
```

`restore` takes `--no-adopt` (always open new windows), `--no-focus` (stay on
the current workspace) and `--notify` (send a summary notification).

### Restore your last session at login

```bash
cat > /tmp/restore-previous <<'EOF'
#!/bin/bash
~/.config/omarchy/plugins/saidness.scenes/bin/scenes restore previous --notify
EOF
omarchy hook install post-boot /tmp/restore-previous
```

## Files

| Path | What |
| --- | --- |
| `~/.config/omarchy/scenes/<name>.json` | your scenes: plain, editable JSON, safe to keep in dotfiles |
| `~/.config/omarchy/scenes/settings.json` | optional settings |
| `~/.local/state/omarchy-scenes/` | the rolling session snapshots and the active scene |

## Settings

All optional, in `~/.config/omarchy/scenes/settings.json`:

```json
{
  "rerun": ["nvim", "lazygit", "btop", "claude", "ssh"],
  "exclude": ["org.gnome.Calculator"],
  "launchTimeout": 15,
  "autosave": true
}
```

- `rerun`: programs that are started again inside restored terminals,
  matched by program name (`nvim`, not `/usr/bin/nvim`). Scripts run as their
  interpreter, so `bin/dev` shows up as `ruby` or `bash`. Anything else gets a
  plain shell in the same directory, so a
  scene never reruns a command you didn't ask for. `["*"]` reruns everything.
  The default covers common editors, git and system TUIs, multiplexers, `ssh`
  and coding agents.
- `exclude`: window classes that are never saved.
- `launchTimeout`: seconds to wait for each app's window.
- `autosave`: set to `false` to turn off the previous-session snapshot.

## How it works

`bin/scenes` reads `hyprctl clients` and `/proc`. For each window it records:

- its geometry relative to its monitor
- for terminals, the shell's working directory and foreground process group
- for everything else, how to start it again

To restore, it walks the scene workspace by workspace. Each window gets a
one-shot `hl.window_rule` (workspace, float, size and position) and its
launch command. It then waits for that window to map before moving on, which
keeps the tiling order. Windows that are already open are reused and moved
into place with `hl.dsp.window.move`.

The plugin's UI uses only the shell's theme tokens (the `[menu]` surface,
spacing and type scale), so it follows every Omarchy theme, light or dark.

## Requirements

Omarchy with the Quickshell shell and Hyprland's Lua config (tested on
Hyprland 0.56), plus `jq`. Both ship with Omarchy.

## License

MIT, see [LICENSE](LICENSE).
