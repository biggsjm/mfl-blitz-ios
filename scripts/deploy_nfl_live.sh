#!/bin/bash
# Deploy the shared cache; reuses the existing private key without copying it.
set -euo pipefail
repo_dir=$(cd "$(dirname "$0")/.." && pwd)
ssh -o BatchMode=yes -o StrictHostKeyChecking=yes hephaestus \
  'umask 077; mkdir -p ~/.local/share/mfl-nfl-live/state ~/.config/systemd/user'
scp -q -o BatchMode=yes -o StrictHostKeyChecking=yes \
  "$repo_dir/services/nfl_live/server.py" "$repo_dir/services/nfl_live/feed.py" \
  "$repo_dir/services/nfl_live/player_identity.py" "$repo_dir/services/nfl_live/player_translations.json" \
  "$repo_dir/services/nfl_live/test_identity.py" \
  "$repo_dir/services/nfl_live/test_defense.py" "$repo_dir/services/nfl_live/test_server.py" "$repo_dir/services/nfl_live/mfl-nfl-live.service" \
  hephaestus:.local/share/mfl-nfl-live/
ssh -o BatchMode=yes -o StrictHostKeyChecking=yes hephaestus 'python3 -' <<'PY'
import os,pathlib,subprocess
os.umask(0o077)
root=pathlib.Path.home()
source=root/'.local/share/mfl-nfl-live'
subprocess.run(['python3','-m','unittest','discover','-s',str(source),'-p','test_*.py'],check=True,
               env=dict(os.environ,PYTHONDONTWRITEBYTECODE='1'))
(root/'.config/systemd/user/mfl-nfl-live.service').write_bytes((source/'mfl-nfl-live.service').read_bytes())
subprocess.run(['systemctl','--user','daemon-reload'],check=True)
subprocess.run(['systemctl','--user','enable','mfl-nfl-live.service'],check=True)
subprocess.run(['systemctl','--user','restart','mfl-nfl-live.service'],check=True)
PY
ssh -o BatchMode=yes -o StrictHostKeyChecking=yes hephaestus \
  'tailscale serve --bg --https=8445 http://127.0.0.1:8793'
