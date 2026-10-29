#!/usr/bin/env bash
set -euo pipefail
# Install the LobsterDeck API as a systemd user service.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$HOME/.config/systemd/user"
install -m 644 "$ROOT/deploy/lobsterdeck.service" "$HOME/.config/systemd/user/lobsterdeck.service"
systemctl --user daemon-reload
systemctl --user enable --now lobsterdeck.service
sleep 1
systemctl --user --no-pager status lobsterdeck.service | head -12
echo
echo "Token: $(cat /vol1/1000/Docker/LobsterDeck/token.txt)"
