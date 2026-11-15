# Change GUI

Flutter Linux app that lists the desktop sessions installed on this machine and lets you choose which one the display manager starts the next time you log in.

## Run

Install Flutter with Linux desktop enabled, then from this directory:

```bash
flutter run -d linux
```

On launch the app reads `*.desktop` files in `/usr/share/xsessions` (shown as X11) and `/usr/share/wayland-sessions` (shown as Wayland). If neither directory contains a session, the window shows an empty state.

## What Switch does

Pick a session and press **Switch**, then confirm.

Switch writes that session's id — the desktop file name without `.desktop` — to `~/.dmrc` as `Session=` under `[Desktop]`. Other lines in the file, such as `Language=`, are left in place. LightDM and other display managers that read `~/.dmrc` use that value at the next login.

The same choice is saved in `~/.config/change_gui/selection.json` (or `$XDG_CONFIG_HOME/change_gui/selection.json`) so the current selection is still marked when you open the app again.

Switch does not log you out and does not reboot. The AccountsService cache that GDM uses is not modified.

## Release bundle

```bash
./tool/build_linux.sh
```

The executable is `build/linux/x64/release/bundle/change_gui`. The script plays a short sound when the build finishes.
