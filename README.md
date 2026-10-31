# Tuck

Tuck tucks the File, Edit, View… menus of whatever app is in front under the app's name, so the left side of the macOS menu bar shows only the name. Click the name and all of the app's menus open from there, as submenus. Keyboard shortcuts keep working as usual.

macOS doesn't let one app remove another app's menus, so Tuck covers them instead: it reads the menu bar through the Accessibility API, lays a strip over the menus that redraws the desktop behind it (live, so moving Aerial wallpapers work too) and pressing an item in Tuck's menu presses the real one. The strip steps aside on screens showing a full-screen app.

## Build

Needs macOS 14 or later on Apple Silicon and the Xcode Command Line Tools.

```sh
./build.sh            # build/Tuck.app
./build.sh --install  # also installs to ~/Applications
```

On first launch Tuck asks for two permissions in System Settings › Privacy & Security: **Accessibility** (to read and press menus) and **Screen & System Audio Recording** (to redraw the desktop behind the strip). It also adds itself to login items; both that and the menu tucking can be switched off from its menu bar icon.

The app is signed ad hoc by default, so macOS forgets its permissions after every rebuild. To keep them, create a self-signed code signing certificate named `Umbrella Yerel Imza` in your login keychain; `build.sh` uses it when present.

## License

Source available, not open source: you may read the code and build it for your own personal, non-commercial use. See [LICENSE](LICENSE).
