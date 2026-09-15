#!/bin/bash
# One-time authorized transfer through a private FIFO: no key on disk locally,
# in process arguments, or in command output. The remote installer refuses overwrite.
set -euo pipefail
transfer_dir=$(mktemp -d /private/tmp/mfl-nfl-key.XXXXXX)
mkfifo -m 600 "$transfer_dir/key"
cleanup() {
    unlink "$transfer_dir/key"
    rmdir "$transfer_dir"
}
trap cleanup EXIT
printf 'Private input FIFO: %s/key\n' "$transfer_dir"
ssh -o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=10 hephaestus \
    'python3 /home/josh/.local/share/mfl-nfl-test/install_key.py' < "$transfer_dir/key"
