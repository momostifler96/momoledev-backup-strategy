#!/bin/bash

# --- Chargement des variables d'environnement ---
ENV_FILE="$(dirname "$0")/.env"
if [ -f "$ENV_FILE" ]; then
    export $(grep -v '^#' "$ENV_FILE" | xargs)
else
    echo -e "\033[0;31m❌ Erreur : Fichier .env introuvable !\033[0m"
    exit 1
fi

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

SOURCE=$1
SAFE_NAME=$(echo $SOURCE | sed 's/\//_/g' | sed 's/^_//')
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
    # Gestion volume Docker
    docker run --rm -v $SOURCE:/data -v $BACKUP_DIR:/backup alpine tar -czf /backup/$(basename $ARCHIVE_FILE) -C /data .
fi

# 2. Chiffrement
echo -e "${LOCK} Chiffrement..."
if ! echo "$GPG_PASSPHRASE" | gpg --batch --yes --passphrase-fd 0 --symmetric --cipher-algo AES256 -o $ENCRYPTED_FILE $ARCHIVE_FILE; then
    send_telegram "⚠️ *Backup ÉCHOUÉ* : [$SOURCE] - Erreur chiffrement."
    exit 1
fi

# 3. Transfert S3
echo -e "${CLOUD} Transfert S3 vers $S3_REMOTE..."
if rclone copy $ENCRYPTED_FILE $S3_REMOTE/backups/$SAFE_NAME/; then
    # 4. Nettoyage
    rclone delete --min-age ${RETENTION_DAYS}d $S3_REMOTE/backups/$SAFE_NAME/
    rm $ARCHIVE_FILE $ENCRYPTED_FILE
    
    echo -e "${GREEN}${CHECK} Succès !${NC}"
    send_telegram "✅ *Backup Réussi*
*Projet:* \`$SOURCE\`
*Fichier:* \`${SAFE_NAME}-$TIMESTAMP.tar.gz.gpg\`"
else
    send_telegram "❌ *Backup ÉCHOUÉ* : [$SOURCE] - Erreur Rclone."
    exit 1
fi