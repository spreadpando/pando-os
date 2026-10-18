#!/usr/bin/env bash
# install.sh — turn a minimal Arch install into the pando Hyprland desktop.
#
#   ./install.sh             full install (desktop + personal apps)
#   ./install.sh --minimal   desktop only, skip packages/apps*.txt
#   ./install.sh --dry-run   print what would happen, change nothing
#   ./install.sh --check     verify every package name still exists, then exit
#
# Safe to re-run: pacman/yay use --needed, stow uses --restow.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG="$ROOT/packages"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"

# stow package -> repo to clone when it isn't already in $DOTFILES_DIR
declare -A DOTFILES=(
  [cli]=https://github.com/spreadpando/cli.git
  [hyprland]=https://github.com/spreadpando/hyperland.git
  [theme]=https://github.com/spreadpando/arch-theme.git
  [rofi]=https://github.com/spreadpando/rofi.git
)
STOW_ORDER=(cli theme rofi hyprland)

SERVICES=(NetworkManager bluetooth sddm reflector.timer paccache.timer)

MINIMAL=0 DRY=0 CHECK=0
for arg in "$@"; do
  case "$arg" in
    --minimal) MINIMAL=1 ;;
    --dry-run) DRY=1 ;;
    --check)   CHECK=1 ;;
    -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

# ── helpers ──────────────────────────────────────────────────────────
c_step=$'\e[1;35m' c_warn=$'\e[1;33m' c_off=$'\e[0m'
step() { printf '\n%s==>%s %s\n' "$c_step" "$c_off" "$*"; }
warn() { printf '%s  !%s %s\n' "$c_warn" "$c_off" "$*" >&2; }
run()  { if ((DRY)); then printf '  + %s\n' "$*"; else "$@"; fi; }

# strip comments/blank lines from one or more package lists
read_list() { sed -e 's/#.*//' -e 's/[[:space:]]//g' "$@" | grep -v '^$' || true; }

has_nvidia() { grep -qs 0x10de /sys/bus/pci/devices/*/vendor; }

ucode() {
  case "$(grep -m1 vendor_id /proc/cpuinfo | awk '{print $3}')" in
    AuthenticAMD) echo amd-ucode ;;
    GenuineIntel) echo intel-ucode ;;
  esac
}

repo_lists() {
  local lists=("$PKG/base.txt" "$PKG/cli.txt" "$PKG/hyprland.txt")
  has_nvidia && lists+=("$PKG/nvidia.txt")
  ((MINIMAL)) || lists+=("$PKG/apps.txt")
  printf '%s\n' "${lists[@]}"
}

aur_lists() {
  local lists=("$PKG/aur.txt")
  ((MINIMAL)) || lists+=("$PKG/apps-aur.txt")
  printf '%s\n' "${lists[@]}"
}

# ── --check: every listed name must resolve in the sync db or the AUR ─
if ((CHECK)); then
  bad=0
  step "checking repo packages"
  for p in $(read_list "$PKG"/base.txt "$PKG"/cli.txt "$PKG"/hyprland.txt "$PKG"/nvidia.txt "$PKG"/apps.txt); do
    pacman -Si "$p" &>/dev/null || pacman -Sg "$p" &>/dev/null || { warn "not in repos: $p"; bad=1; }
  done
  step "checking AUR packages"
  mapfile -t aur < <(read_list "$PKG"/aur.txt "$PKG"/apps-aur.txt)
  query=$(printf '&arg[]=%s' "${aur[@]}")
  found=$(curl -fsS "https://aur.archlinux.org/rpc/v5/info?${query#&}" | jq -r '.results[].Name')
  for p in "${aur[@]}"; do
    grep -qx "$p" <<<"$found" || { warn "not in AUR: $p"; bad=1; }
  done
  ((bad)) && exit 1
  echo "all package names resolve"
  exit 0
fi

# ── preflight ────────────────────────────────────────────────────────
[[ $EUID -ne 0 ]] || { echo "run as your normal user, not root (sudo is used where needed)" >&2; exit 1; }
[[ -f /etc/arch-release ]] || { echo "this only targets Arch Linux" >&2; exit 1; }
((DRY)) && echo "dry run — nothing will be changed"
has_nvidia && echo "NVIDIA GPU detected — including packages/nvidia.txt"
((MINIMAL)) && echo "minimal — skipping personal apps"

# ── pacman.conf ──────────────────────────────────────────────────────
step "pacman.conf: multilib, color, parallel downloads"
run sudo sed -i \
  -e '/^#\[multilib\]/,/^#Include/ s/^#//' \
  -e 's/^#Color/Color/' \
  -e 's/^#ParallelDownloads/ParallelDownloads/' \
  /etc/pacman.conf

# ── mirrors ──────────────────────────────────────────────────────────
step "mirrors: reflector"
run sudo pacman -Sy --needed --noconfirm reflector
run sudo install -Dm644 "$ROOT/etc/xdg/reflector/reflector.conf" /etc/xdg/reflector/reflector.conf
if ! run sudo systemctl start reflector.service; then
  warn "reflector failed — keeping the existing mirrorlist"
  [[ -s /etc/pacman.d/mirrorlist ]] || run sudo install -m644 "$ROOT/etc/pacman.d/mirrorlist.fallback" /etc/pacman.d/mirrorlist
fi

# ── repo packages ────────────────────────────────────────────────────
step "repo packages"
mapfile -t lists < <(repo_lists)
mapfile -t pkgs < <(read_list "${lists[@]}"; ucode)
# pacman -T honours `provides`, so e.g. fastfetch-gif-git counts as fastfetch
# instead of triggering a conflict prompt that --noconfirm would answer "no"
missing=$(pacman -T "${pkgs[@]}" || true)
echo "  $(wc -w <<<"$missing") package(s) to install"
[[ -n $missing ]] && fmt -w 100 <<<"$missing" | sed 's/^/    /'
run sudo pacman -Syu --noconfirm
# shellcheck disable=SC2086
[[ -z $missing ]] || run sudo pacman -S --needed --noconfirm $missing

# ── AUR ──────────────────────────────────────────────────────────────
step "AUR helper (yay)"
if ! command -v yay &>/dev/null; then
  tmp=$(mktemp -d)
  run git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin"
  ((DRY)) || (cd "$tmp/yay-bin" && makepkg -si --noconfirm)
  rm -rf "$tmp"
fi

step "AUR packages"
mapfile -t lists < <(aur_lists)
mapfile -t aur < <(read_list "${lists[@]}")
run yay -S --needed --noconfirm --answerclean None --answerdiff None "${aur[@]}"

# ── system config ────────────────────────────────────────────────────
step "system config"
run sudo install -Dm644 "$ROOT/etc/sddm.conf.d/10-pando.conf" /etc/sddm.conf.d/10-pando.conf

# ── dotfiles ─────────────────────────────────────────────────────────
step "dotfiles → $DOTFILES_DIR"
run mkdir -p "$DOTFILES_DIR"
stow_failed=()
for name in "${STOW_ORDER[@]}"; do
  if [[ ! -d "$DOTFILES_DIR/$name" ]]; then
    run git clone "${DOTFILES[$name]}" "$DOTFILES_DIR/$name" \
      || { warn "could not clone $name from ${DOTFILES[$name]}"; stow_failed+=("$name"); continue; }
  fi
  # simulate first so a conflict leaves $HOME untouched
  if ((DRY)) || stow -n -d "$DOTFILES_DIR" -t "$HOME" --restow "$name" 2>/dev/null; then
    run stow -d "$DOTFILES_DIR" -t "$HOME" --restow "$name"
  else
    warn "stow conflict in '$name' — existing files in \$HOME are in the way:"
    stow -n -d "$DOTFILES_DIR" -t "$HOME" --restow "$name" 2>&1 | sed 's/^/      /' >&2 || true
    stow_failed+=("$name")
  fi
done

# fonts shipped inside the dotfiles (feather, Iosevka/JetBrains Nerd) land in ~/.local/share/fonts
run fc-cache -f

# per-machine Hyprland settings (never in git); monitors get filled in by hand later
HYPR_LOCAL="$HOME/.config/hypr/local.lua"
if [[ ! -e $HYPR_LOCAL ]]; then
  has_nvidia && nv=true || nv=false
  if ((DRY)); then
    echo "  + write $HYPR_LOCAL (nvidia = $nv, no monitors)"
  else
    mkdir -p "${HYPR_LOCAL%/*}"
    cat >"$HYPR_LOCAL" <<EOF
-- Per-machine Hyprland settings; see local.example.lua next to this file.
-- Fill in monitors (\`hyprctl monitors\`) to get the spanned wallpaper.
return {
    monitors   = {},
    workspaces = {},
    nvidia     = $nv,
    env        = {},
}
EOF
  fi
fi

# ── shell ────────────────────────────────────────────────────────────
step "shell: fish + plugins + nvm"
[[ -d "$HOME/.nvm" ]] || run git clone --depth 1 https://github.com/nvm-sh/nvm.git "$HOME/.nvm"
[[ "$(getent passwd "$USER" | cut -d: -f7)" == /usr/bin/fish ]] || run sudo chsh -s /usr/bin/fish "$USER"
run fish -c 'fisher update'

# ── services ─────────────────────────────────────────────────────────
step "services"
((MINIMAL)) || SERVICES+=(docker)
run sudo systemctl enable "${SERVICES[@]}"
((MINIMAL)) || run sudo usermod -aG docker "$USER"

# ── theme ────────────────────────────────────────────────────────────
step "theme"
if command -v theme-apply &>/dev/null || [[ -x "$HOME/.local/bin/theme-apply" ]]; then
  run "$HOME/.local/bin/theme-apply" || warn "theme-apply failed (missing wallpaper? check ~/.config/theme.conf)"
else
  warn "theme-apply not found — is the theme dotfiles package stowed?"
fi

# ── done ─────────────────────────────────────────────────────────────
step "done"
if ((${#stow_failed[@]})); then
  warn "these dotfile packages were not stowed: ${stow_failed[*]}"
  warn "fix the conflicts above, then re-run ./install.sh"
fi
echo "reboot, pick Hyprland in sddm, and you're home."
