#!/bin/bash
set -euo pipefail
umask 077

BACKUP_DIR="/home/anuj/kubernetes-backups"
RESTIC_REPO="/home/anuj/immich-encrypted-backup"
RESTIC_PASS_FILE="/home/anuj/.config/restic/password"
ARCHIVE_DIR="gdrive:Homelab-Archive/$(date +%F)"

FILTER_FILE="$(mktemp)"
trap 'rm -f "$FILTER_FILE"' EXIT

echo "=== Ultimate Homelab Backup Started: $(date) ==="

# 1. Network Check (exit non-zero so systemd marks the run as failed)
if ! ping -c 1 -W 5 8.8.8.8 &>/dev/null; then
  echo "ERROR: Network offline. Backup failed." >&2
  exit 1
fi

# 2. Verify restic password file exists outside synced folders
if [[ ! -r "$RESTIC_PASS_FILE" ]]; then
  echo "ERROR: Restic password file missing at $RESTIC_PASS_FILE" >&2
  exit 1
fi

# 3. Export cluster secrets, SealedSecrets master key & Vaultwarden DB
#    Stored locally in $BACKUP_DIR and encrypted into restic (NEVER synced plaintext to GDrive)
echo "-> Exporting cluster state and Vaultwarden SQLite..."
mkdir -p "$BACKUP_DIR"

sqlite3 /home/anuj/vaultwarden/data/db.sqlite3 ".backup '${BACKUP_DIR}/vaultwarden.sqlite3'"

kubectl get secret -n kube-system \
  -l sealed-secrets.bitnami.com/sealed-secrets-key \
  -o yaml > "${BACKUP_DIR}/sealed-secrets-key.yaml"

kubectl get secret argocd-secret -n argocd -o yaml > "${BACKUP_DIR}/argocd-secret.yaml"
kubectl get secret operator-oauth -n tailscale -o yaml > "${BACKUP_DIR}/tailscale-oauth.yaml" 2>/dev/null || true

# 4. Encrypted restic snapshot (Immich library + cluster secrets + Vaultwarden DB)
echo "-> Running encrypted restic snapshot..."
restic -r "$RESTIC_REPO" \
  --password-file "$RESTIC_PASS_FILE" \
  backup /home/anuj/immich-app/library "$BACKUP_DIR"

echo "-> Pruning old restic snapshots..."
restic -r "$RESTIC_REPO" \
  --password-file "$RESTIC_PASS_FILE" \
  forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune

# 5. Build rclone whitelist (excludes plaintext secrets and restic password)
cat << 'EOF' > "$FILTER_FILE"
- /navidrome/data/cache/**
- /documents/restic-password.txt
+ /adguard/**
+ /documents/**
+ /immich-encrypted-backup/**
+ /navidrome/**
+ /opencloud/**
+ /pictures/**
+ /vaultwarden/**
+ /backups/**
+ /downloads/**
- **
EOF

# 6. Sync whitelist to Google Drive with deletion safety net (--backup-dir)
echo "-> Syncing allowed folders to Google Drive..."
rclone sync /home/anuj gdrive:Homelab \
  --filter-from "$FILTER_FILE" \
  --backup-dir "$ARCHIVE_DIR" \
  --links \
  --fast-list \
  --verbose

echo "=== Ultimate Backup Completed Successfully: $(date) ==="
