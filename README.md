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

Switch writes the session id — the desktop file name without `.desktop` — where each display manager reads it:

- LightDM: `Session=` under `[Desktop]` in `~/.dmrc`. Other lines, such as `Language=`, stay in place.
- GDM: `Session`, `XSession`, and `SessionType` (`x11` or `wayland`) on the AccountsService user, via the system bus when the user is allowed to change their own account. The cache file is `/var/lib/AccountsService/users/<name>`.
- SDDM has no per-user session file. Its machine-wide `/var/lib/sddm/state.conf` is left unchanged.

The same choice is saved in `~/.config/change_gui/selection.json` (or `$XDG_CONFIG_HOME/change_gui/selection.json`) so the current selection stays marked when you open the app again. The window lists each file that was written.

Switch does not log you out and does not reboot. Log out and back in for the login screen to start the session you confirmed.

## Release bundle

```bash
./tool/build_linux.sh
```

The executable is `build/linux/x64/release/bundle/change_gui`. The script plays a short sound when the build finishes.
