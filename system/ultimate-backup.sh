#!/bin/bash
set -e

echo "=== Ultimate Homelab Backup Started: $(date) ==="

# 1. Network Check
if ! ping -c 1 8.8.8.8 &>/dev/null; then
  echo "Network offline. Postponing backup task."
  exit 0
fi

# 2. CREATE THE WHITELIST FILTER
cat << 'EOF' > /home/anuj/.local/bin/rclone-filter.txt
- /navidrome/data/cache/**
+ /adguard/**
+ /documents/**
+ /immich-encrypted-backup/**
+ /immich-app/docker-compose.yml
+ /immich-app/.env
+ /navidrome/**
+ /opencloud/**
+ /pictures/**
+ /vaultwarden/**
+ /kubernetes-backups/**
+ /backups/**
+ /downloads/**
- **
EOF

# 3. KUBERNETES SECRETS & VAULTWARDEN STATE
echo "-> Exporting state and secrets..."
mkdir -p /home/anuj/kubernetes-backups

# Dump Vaultwarden DB 
sqlite3 /home/anuj/vaultwarden/data/db.sqlite3 ".backup '/home/anuj/kubernetes-backups/vaultwarden.sqlite3'"

# Dump default namespace secrets and ArgoCD admin credentials
kubectl get secrets --field-selector type=Opaque -n default -o yaml > /home/anuj/kubernetes-backups/default-secrets.yaml
kubectl get secret argocd-secret -n argocd -o yaml > /home/anuj/kubernetes-backups/argocd-secret.yaml

# 4. IMMICH ENCRYPTED SNAPSHOT
echo "-> Running local Immich encrypted snapshot..."
restic -r /home/anuj/immich-encrypted-backup --password-file /home/anuj/documents/restic-password.txt backup /home/anuj/immich-app/library

# 5. SYNC ONLY THE WHITELIST TO GOOGLE DRIVE
echo "-> Syncing allowed folders to Google Drive..."
rclone sync /home/anuj gdrive:Homelab \
  --filter-from /home/anuj/.local/bin/rclone-filter.txt \
  --links \
  --fast-list --verbose

echo "-> Cleaning up local filter file..."
rm /home/anuj/.local/bin/rclone-filter.txt

echo "=== Ultimate Backup Completed Successfully: $(date) ==="
