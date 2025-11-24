#!/bin/bash
set -e

# 環境変数から取得
SSH_USER=${SSH_USER:-sample-user}
SSH_SERVER=${SSH_SERVER:-sample-server}

# リモートフォワード（-R）カンマ区切り
# 例: "8097:192.168.1.9:8097,8098:192.168.1.10:8080"
IFS=',' read -r -a REMOTE_FORWARD_ARRAY <<< "${PORT_FORWARD_LIST:-}"

# ローカルフォワード（-L）カンマ区切り
# 例: "8080:192.168.1.20:80,8443:192.168.1.21:443"
IFS=',' read -r -a LOCAL_FORWARD_ARRAY <<< "${LOCAL_FORWARD_LIST:-}"

# SSHオプション生成
SSH_FORWARD_OPTS=""

for PF in "${REMOTE_FORWARD_ARRAY[@]}"; do
    SSH_FORWARD_OPTS="$SSH_FORWARD_OPTS -R $PF"
done

for PF in "${LOCAL_FORWARD_ARRAY[@]}"; do
    SSH_FORWARD_OPTS="$SSH_FORWARD_OPTS -L $PF"
done

# 無限ループで接続維持
while true; do
    echo "[$(date)] Connecting to $SSH_SERVER..."
    ssh -o StrictHostKeyChecking=no -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -N $SSH_FORWARD_OPTS ${SSH_USER}@${SSH_SERVER}
    
    echo "[$(date)] SSH connection lost. Reconnecting in 5 seconds..."
    sleep 5
done
