#!/bin/bash
# Requires a provisioned owner-only testers.json. No public route is enabled here.
set -euo pipefail
repo_dir=$(cd "$(dirname "$0")/.." && pwd)
ssh -o BatchMode=yes -o StrictHostKeyChecking=yes hephaestus \
  'umask 077; mkdir -p ~/.local/share/mfl-tester-gateway/state ~/.config/mfl-tester-gateway ~/.config/systemd/user'
scp -q -o BatchMode=yes -o StrictHostKeyChecking=yes \
  "$repo_dir/services/tester_gateway/server.py" "$repo_dir/services/tester_gateway/test_gateway.py" \
  "$repo_dir/services/tester_gateway/mfl-tester-gateway.service" hephaestus:.local/share/mfl-tester-gateway/
ssh -o BatchMode=yes -o StrictHostKeyChecking=yes hephaestus 'python3 -' <<'PY'
import os,pathlib,subprocess
os.umask(0o077)
root=pathlib.Path.home(); source=root/'.local/share/mfl-tester-gateway'
config=root/'.config/mfl-tester-gateway/testers.json'
if not config.is_file() or config.stat().st_mode & 0o077:
    raise SystemExit('Provision an owner-only tester configuration first.')
subprocess.run(['python3','-m','unittest','discover','-s',str(source),'-p','test_*.py'],check=True,
               env=dict(os.environ,PYTHONDONTWRITEBYTECODE='1'))
(root/'.config/systemd/user/mfl-tester-gateway.service').write_bytes((source/'mfl-tester-gateway.service').read_bytes())
subprocess.run(['systemctl','--user','daemon-reload'],check=True)
subprocess.run(['systemctl','--user','enable','--now','mfl-tester-gateway.service'],check=True)
subprocess.run(['systemctl','--user','restart','mfl-tester-gateway.service'],check=True)
PY
