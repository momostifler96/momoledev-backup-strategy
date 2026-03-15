#!/bin/bash

# --- Chargement des variables d'environnement ---
SCRIPT_DIR="$(dirname "$0")"
ENV_FILE="$SCRIPT_DIR/.env"
if [ -f "$ENV_FILE" ]; then
    export $(grep -v '^#' "$ENV_FILE" | xargs)
else
    echo "❌ Fichier .env introuvable : $ENV_FILE"
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
GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; NC='\033[0m'

if [ -z "$1" ]; then
    echo "Usage: ./restore.sh nom_dossier_ou_volume"
    exit 1
fi

SOURCE_INPUT="${1#./}"
SOURCE_INPUT="${SOURCE_INPUT#/}"
SOURCE_NAME=$(echo "$SOURCE_INPUT" | sed 's/\//_/g' | sed 's/^_//')
R2_PREFIX="backups/$SOURCE_NAME/"

if [[ -z "${R2_BUCKET:-}" || -z "${R2_ACCOUNT_ID:-}" ]]; then
  echo "❌ Variables R2 manquantes dans .env (R2_ACCOUNT_ID, R2_BUCKET, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY)."
  exit 1
fi

echo -e "${BLUE}🔍 Liste des archives pour $1 :${NC}"
r2_list "$R2_PREFIX" | sed 's/^/  📦 /'

echo -e "\n${YELLOW}Copiez-collez le nom du fichier à restaurer :${NC}"
read -r FILENAME

if [[ "$FILENAME" == */* ]]; then
  LOCAL_FILE="$(basename "$FILENAME")"
  r2_download "$FILENAME" "./$LOCAL_FILE" || exit 1
else
  LOCAL_FILE="$FILENAME"
  r2_download "${R2_PREFIX}${FILENAME}" "./$LOCAL_FILE" || exit 1
fi
RESTORE_DIR="restored-files"
mkdir -p "$RESTORE_DIR"
if ! echo "$GPG_PASSPHRASE" | gpg --batch --yes --passphrase-fd 0 --decrypt --output "$RESTORE_DIR/restored.tar.gz" "$LOCAL_FILE"; then
  echo -e "\033[0;31m❌ Échec du déchiffrement (vérifiez GPG_PASSPHRASE dans .env).\033[0m"
  exit 1
fi

echo -e "${GREEN}✅ Déchiffré.${NC}"
echo -e "${BLUE}📦 Désarchivage dans $RESTORE_DIR/ ...${NC}"
if ! tar -xzf "$RESTORE_DIR/restored.tar.gz" ; then
  echo -e "\033[0;31m❌ Échec du désarchivage.\033[0m"
  exit 1
fi
rm -f "$RESTORE_DIR/restored.tar.gz"
echo -e "${GREEN}✅ Restauration terminée."