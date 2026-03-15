#!/bin/bash

# --- Chargement des variables d'environnement ---
SCRIPT_DIR="$(dirname "$0")"
ENV_FILE="$SCRIPT_DIR/.env"
if [ -f "$ENV_FILE" ]; then
    export $(grep -v '^#' "$ENV_FILE" | xargs)
else
    echo -e "\033[0;31m❌ Erreur : Fichier .env introuvable !\033[0m"
    exit 1
fi

# --- Import des fonctions R2 (curl) ---
export R2_ENV_FILE="$ENV_FILE"
# shellcheck source=curl_r2.sh
source "$SCRIPT_DIR/curl_r2.sh"

# --- Normalisation passphrase (retire les "" ou '' éventuels du .env) ---
if [[ -n "${GPG_PASSPHRASE:-}" ]]; then
  GPG_PASSPHRASE="${GPG_PASSPHRASE#[\"']}"
  GPG_PASSPHRASE="${GPG_PASSPHRASE%[\"']}"
  export GPG_PASSPHRASE
fi

# --- Rétention : durée de conservation des backups (défaut 7 jours) ---
RETENTION_DAYS="${RETENTION_DAYS:-7}"

# --- Couleurs et Icônes ---
GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
CHECK="✅"; INFO="ℹ️"; LOCK="🔒"; CLOUD="☁️"; ERROR="❌"

# --- Configuration Backup (utilisant les variables du .env) ---
BACKUP_DIR="/tmp/backups"

# --- Fonction Notification Telegram ---
send_telegram() {
    local message=$1
    curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage" \
        -d chat_id="$TELEGRAM_CHAT_ID" \
        -d text="$message" -d parse_mode="Markdown" > /dev/null
}

# --- Vérification Paramètre ---
if [ -z "$1" ]; then
    echo -e "${ERROR} ${RED}Erreur : Argument manquant (chemin ou volume).${NC}"
    exit 1
fi

# Conserver le chemin absolu pour que -d/-f et tar trouvent le bon dossier (ne pas enlever le / initial)
SOURCE="${1#./}"
SAFE_NAME=$(echo "$SOURCE" | sed 's/\//_/g' | sed 's/^_//')
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
ARCHIVE_FILE="$BACKUP_DIR/${SAFE_NAME}-$TIMESTAMP.tar.gz"
ENCRYPTED_FILE="$ARCHIVE_FILE.gpg"

mkdir -p $BACKUP_DIR
echo -e "${BLUE}--- 🚀 Backup : $SOURCE ---${NC}"

# 1. Archivage
echo -e "${INFO} Compression..."
if [ -d "$SOURCE" ] || [ -f "$SOURCE" ]; then
    tar -czf $ARCHIVE_FILE -C "$(dirname "$SOURCE")" "$(basename "$SOURCE")"
else
    # Gestion volume Docker (nom sans /)
    if [[ "$SOURCE" == */* ]]; then
      echo -e "${RED}${ERROR} Dossier/fichier introuvable : $SOURCE${NC}"
      echo "  Utilisez un chemin absolu pour un dossier sur l'hôte, ex. : /home/livo-ride-supabase/livo-ride-supabase/volumes/storage"
      exit 1
    fi
    docker run --rm -v "$SOURCE:/data" -v "$BACKUP_DIR:/backup" alpine tar -czf /backup/$(basename $ARCHIVE_FILE) -C /data .
fi

# 2. Chiffrement
echo -e "${LOCK} Chiffrement..."
if ! echo "$GPG_PASSPHRASE" | gpg --batch --yes --passphrase-fd 0 --symmetric --cipher-algo AES256 -o $ENCRYPTED_FILE $ARCHIVE_FILE; then
    send_telegram "⚠️ *Backup ÉCHOUÉ* : [$SOURCE] - Erreur chiffrement."
    exit 1
fi

# 3. Transfert vers Cloudflare R2
R2_PREFIX="backups/$SAFE_NAME/"
R2_KEY="${R2_PREFIX}$(basename "$ENCRYPTED_FILE")"

if [[ -z "${R2_BUCKET:-}" || -z "${R2_ACCOUNT_ID:-}" ]]; then
  echo -e "${RED}${ERROR} Variables R2 manquantes dans .env (R2_ACCOUNT_ID, R2_BUCKET, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY).${NC}"
  exit 1
fi

echo -e "${CLOUD} Transfert R2 vers $R2_KEY..."
if r2_upload "$ENCRYPTED_FILE" "$R2_KEY"; then
  # 4. Rétention : supprimer les backups de plus de RETENTION_DAYS (ex. 7 jours)
  echo -e "${INFO} Nettoyage des backups de plus de ${RETENTION_DAYS} jours..."
  while IFS= read -r key; do
    [[ -z "$key" ]] && continue
    fname=$(basename "$key")
    if [[ "$fname" =~ -([0-9]{8}_[0-9]{6})\.tar\.gz\.gpg$ ]]; then
      filedate="${BASH_REMATCH[1]}"
      filedate_epoch=$(date -d "${filedate:0:4}-${filedate:4:2}-${filedate:6:2} ${filedate:9:2}:${filedate:11:2}:${filedate:13:2}" +%s 2>/dev/null || echo 0)
      now_epoch=$(date +%s)
      age_days=$(( (now_epoch - filedate_epoch) / 86400 ))
      if (( age_days >= RETENTION_DAYS )); then
        r2_delete "$key" 2>/dev/null && echo -e "  ${INFO} Supprimé : $fname (${age_days} jours)"
      fi
    fi
  done < <(r2_list "$R2_PREFIX")
  rm -f $ARCHIVE_FILE $ENCRYPTED_FILE
  echo -e "${GREEN}${CHECK} Succès !${NC}"
  send_telegram "✅ *Backup Réussi*
*Projet:* \`$SOURCE\`
*Fichier:* \`${SAFE_NAME}-$TIMESTAMP.tar.gz.gpg\`"
else
  send_telegram "❌ *Backup ÉCHOUÉ* : [$SOURCE] - Erreur R2."
  exit 1
fi