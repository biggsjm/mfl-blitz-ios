#!/bin/bash
# Deploy only the private MFL Live Activity service. No APNs key is copied here.
set -euo pipefail
repo_dir=$(cd "$(dirname "$0")/.." && pwd)
ssh -o BatchMode=yes -o StrictHostKeyChecking=yes hephaestus \
  'umask 077; mkdir -p ~/.local/share/mfl-live-activity/state ~/.config/mfl-live-activity ~/.config/systemd/user'
scp -q -o BatchMode=yes -o StrictHostKeyChecking=yes \
  "$repo_dir/services/live_activity/server.py" "$repo_dir/services/live_activity/scoring.py" \
  "$repo_dir/services/live_activity/timeline.py" \
  "$repo_dir/services/live_activity/mfl_requests.py" "$repo_dir/services/live_activity/test_mfl_requests.py" \
  "$repo_dir/services/live_activity/nfl_context.py" "$repo_dir/services/live_activity/lineup_alerts.py" \
  "$repo_dir/services/live_activity/test_game_day.py" "$repo_dir/services/live_activity/test_server.py" "$repo_dir/services/live_activity/mfl-live-activity.service" \
  hephaestus:.local/share/mfl-live-activity/
ssh -o BatchMode=yes -o StrictHostKeyChecking=yes hephaestus 'python3 -' <<'PY'
import json,os,pathlib,subprocess
os.umask(0o077)
root=pathlib.Path.home()
path=root/'.config/mfl-live-activity/config.json'
if not path.exists():
    status=json.loads(subprocess.check_output(['tailscale','status','--json']))
    login=status.get('User',{}).get(str(status['Self'].get('UserID','')),{}).get('LoginName')
    if not login:
        raise SystemExit('Configure the allowed owner identity before starting the service.')
    config={'allowedLogins':[login], 'leagues':{'2026.41333':'www45.myfantasyleague.com'},
            'apnsTeamID':'CP6ZMDE546', 'apnsKeyID':'',
            'apnsKeyFile':str(root/'.config/mfl-live-activity/apns-key.p8')}
    with path.open('x') as f: json.dump(config,f)
source=root/'.local/share/mfl-live-activity'
subprocess.run(['python3','-m','unittest','discover','-s',str(source),'-p','test_*.py'],check=True,
               env=dict(os.environ,PYTHONDONTWRITEBYTECODE='1'))
(root/'.config/systemd/user/mfl-live-activity.service').write_bytes((source/'mfl-live-activity.service').read_bytes())
subprocess.run(['systemctl','--user','daemon-reload'],check=True)
subprocess.run(['systemctl','--user','enable','--now','mfl-live-activity.service'],check=True)
subprocess.run(['systemctl','--user','restart','mfl-live-activity.service'],check=True)
PY
# Independent private HTTPS port; preserves the historical NFL test route on 8443.
ssh -o BatchMode=yes -o StrictHostKeyChecking=yes hephaestus \
  'tailscale serve --bg --https=8444 http://127.0.0.1:8792'
