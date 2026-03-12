#!/bin/bash
GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; NC='\033[0m'
S3_REMOTE="my_s3_r2:nom-du-bucket"
GPG_PASSPHRASE="VOTRE_MOT_DE_PASSE_TRES_SECURISE"

if [ -z "$1" ]; then
    echo "Usage: ./restore.sh nom_dossier_ou_volume"
    exit 1
fi

SOURCE_NAME=$(echo $1 | sed 's/\//_/g' | sed 's/^_//')
REMOTE_PATH="$S3_REMOTE/backups/$SOURCE_NAME"

echo -e "${BLUE}🔍 Liste des archives pour $1 :${NC}"
rclone lsf $REMOTE_PATH | sed 's/^/  📦 /'

echo -e "\n${YELLOW}Copiez-collez le nom du fichier à restaurer :${NC}"
read FILENAME

rclone copy "$REMOTE_PATH/$FILENAME" .
echo "$GPG_PASSPHRASE" | gpg --batch --yes --passphrase-fd 0 --decrypt --output restored.tar.gz "$FILENAME"

echo -e "${GREEN}✅ Déchiffré. L'archive 'restored.tar.gz' est prête.${NC}"