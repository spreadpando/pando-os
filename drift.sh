#!/usr/bin/env bash
# drift.sh — compare this machine against packages/*.txt so the lists stay honest.
#
#   unlisted:  explicitly installed here, but in no list (add it, or remove it from the system)
#   missing:   in a list, but not installed here
set -euo pipefail

PKG="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/packages"
listed=$(sed -e 's/#.*//' -e 's/[[:space:]]//g' "$PKG"/*.txt | grep -v '^$' | sort -u)

echo "== unlisted (explicit here, in no list)"
comm -23 <(pacman -Qqe | sort -u) <(echo "$listed") | fmt -w 100 | sed 's/^/  /'

echo
echo "== missing (listed, not installed)"
comm -13 <(pacman -Qq | sort -u) <(echo "$listed") | fmt -w 100 | sed 's/^/  /'
