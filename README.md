# pando-os

One script that turns a minimal Arch install into my Hyprland desktop.
It's not a real distro: it's plain Arch with my package lists, mirror setup and dotfiles applied on top.

## Fresh machine

1. Boot the Arch ISO and run `archinstall` with a **minimal** profile: no desktop, NetworkManager for networking, and a normal user with sudo.
2. Reboot, log in, and run:

```bash
sudo pacman -S --needed git
git clone https://github.com/spreadpando/pando-os.git ~/Projects/pando-os
cd ~/Projects/pando-os
./install.sh            # or --minimal for desktop only, --dry-run to preview
```

3. Reboot and pick Hyprland in SDDM.

## Layout

| path | what |
|---|---|
| `packages/base.txt` | kernel, base-devel, network, pipewire, fonts |
| `packages/cli.txt` | shell and terminal tools (pairs with the `cli` dotfiles) |
| `packages/hyprland.txt` | compositor, portals, waybar, dunst, rofi, applets, wallpaper pipeline, theming |
| `packages/nvidia.txt` | installed only when an NVIDIA GPU is detected |
| `packages/aur.txt` | AUR packages the desktop needs (mpvpaper, sddm theme, GTK theme, cursors) |
| `packages/apps.txt`, `apps-aur.txt` | personal apps, skipped with `--minimal` |
| `assets/` | wallpapers and rofi images, laid out like `$HOME`; copied in without overwriting anything |
| `etc/` | reflector config, SDDM theme config, fallback mirrorlist |
| `install.sh` | the bootstrap (idempotent, safe to re-run) |
| `drift.sh` | shows packages installed here but missing from every list, and the reverse |

The CPU microcode package (`amd-ucode` / `intel-ucode`) is chosen automatically.

## Dotfiles

These are stowed from `~/.dotfiles`, and any that are missing get cloned from GitHub:
`cli`, `theme` (arch-theme), `rofi`, `hyprland` (hyperland). The URLs are at the top of `install.sh`.
Fonts that waybar and rofi need (feather, Iosevka/JetBrains Nerd) ship inside those repos; image assets live here in `assets/`.
Per-machine Hyprland settings go in `~/.config/hypr/local.lua`, which the installer seeds.

## Keeping it current

```bash
./drift.sh              # what's on this machine but not in the lists?
./install.sh --check    # does every listed package still exist?
```

## Deliberately left out

The i3/X11 stack (i3, polybar, picom, conky, autorandr, feh, most `xorg-*` tools), KDE and Cinnamon leftovers, `endeavouros-keyring`, `xf86-video-vesa`, `nvidia-hook` (no longer in the AUR) and one-off tools. Use `drift.sh` to see the full list on a given machine.
