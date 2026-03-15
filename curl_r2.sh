#!/usr/bin/env bash
# ============================================================
#  r2_functions.sh — Upload / Download Cloudflare R2 via curl
#  Usage :
#    source r2_functions.sh
#    r2_upload  /chemin/local/fichier.txt  remote/fichier.txt
#    r2_download remote/fichier.txt        /chemin/local/copie.txt
# ============================================================

# ---------- chargement du .env ----------
_r2_load_env() {
  local env_file="${R2_ENV_FILE:-.env}"          # surcharge possible via variable

  if [[ ! -f "$env_file" ]]; then
    echo "[r2] ❌  Fichier .env introuvable : $env_file" >&2
    return 1
  fi

  # Charge uniquement les lignes KEY=VALUE (ignore commentaires et lignes vides)
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*#  ]] && continue   # commentaire
    [[ -z "${line//[[:space:]]/}" ]] && continue   # ligne vide
    # Export seulement si la ligne ressemble à VAR=valeur
    if [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
      export "${line?}"
    fi
  done < "$env_file"

  # Vérification des variables obligatoires
  local missing=()
  for var in R2_ACCOUNT_ID R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY R2_BUCKET; do
    [[ -z "${!var}" ]] && missing+=("$var")
  done

  if (( ${#missing[@]} > 0 )); then
    echo "[r2] ❌  Variables manquantes dans $env_file : ${missing[*]}" >&2
    return 1
  fi
}

# ---------- upload ----------
# Usage : r2_upload <source_locale> <destination_r2>
# Exemple: r2_upload ./rapport.pdf  docs/rapport.pdf
r2_upload() {
  local src="$1"
  local dst="$2"

  # Validation des arguments
  if [[ -z "$src" || -z "$dst" ]]; then
    echo "Usage : r2_upload <source_locale> <destination_r2>" >&2
    return 1
  fi
  if [[ ! -f "$src" ]]; then
    echo "[r2] ❌  Fichier source introuvable : $src" >&2
    return 1
  fi

  _r2_load_env || return 1

  local endpoint="https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
  local url="${endpoint}/${R2_BUCKET}/${dst}"

  echo "[r2] ⬆️  Upload  : $src → $url"

  curl --silent --show-error --fail \
    --request PUT "$url" \
    --user "${R2_ACCESS_KEY_ID}:${R2_SECRET_ACCESS_KEY}" \
    --aws-sigv4 "aws:amz:auto:s3" \
    --header "Content-Type: application/octet-stream" \
    --data-binary "@${src}"

  local exit_code=$?
  if (( exit_code == 0 )); then
    echo "[r2] ✅  Upload réussi : $dst"
  else
    echo "[r2] ❌  Échec upload (code $exit_code)" >&2
  fi
  return $exit_code
}

# ---------- download ----------
# Usage : r2_download <source_r2> <destination_locale>
# Exemple: r2_download docs/rapport.pdf ./copie-rapport.pdf
r2_download() {
  local src="$1"
  local dst="$2"

  # Validation des arguments
  if [[ -z "$src" || -z "$dst" ]]; then
    echo "Usage : r2_download <source_r2> <destination_locale>" >&2
    return 1
  fi

  _r2_load_env || return 1

  local endpoint="https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
  local url="${endpoint}/${R2_BUCKET}/${src}"

  echo "[r2] ⬇️  Download : $url → $dst"

  # Crée le dossier de destination si nécessaire
  mkdir -p "$(dirname "$dst")"

  curl --silent --show-error --fail \
    --request GET "$url" \
    --user "${R2_ACCESS_KEY_ID}:${R2_SECRET_ACCESS_KEY}" \
    --aws-sigv4 "aws:amz:auto:s3" \
    --output "$dst"

  local exit_code=$?
  if (( exit_code == 0 )); then
    echo "[r2] ✅  Download réussi : $dst"
  else
    echo "[r2] ❌  Échec download (code $exit_code)" >&2
    rm -f "$dst"   # nettoie le fichier partiel
  fi
  return $exit_code
}

# ---------- list (préfixe R2) ----------
# Usage : r2_list <préfixe_r2>
# Affiche un nom de fichier par ligne (clés sous le préfixe).
# Exemple: r2_list backups/mon-dossier/
r2_list() {
  local prefix="${1:-}"

  if [[ -z "$prefix" ]]; then
    echo "Usage : r2_list <préfixe_r2>" >&2
    return 1
  fi

  _r2_load_env || return 1

  local endpoint="https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
  local base_url="${endpoint}/${R2_BUCKET}"

  local xml
  xml=$(curl --silent --show-error --fail -G "$base_url" \
    --data-urlencode "list-type=2" \
    --data-urlencode "prefix=$prefix" \
    --user "${R2_ACCESS_KEY_ID}:${R2_SECRET_ACCESS_KEY}" \
    --aws-sigv4 "aws:amz:auto:s3") || return 1

  echo "$xml" | grep -oE '<Key>[^<]+</Key>' | sed 's/<[^>]*>//g'
}

# ---------- delete (une clé R2) ----------
# Usage : r2_delete <chemin_r2>
# Exemple: r2_delete backups/mon-dossier/vieux-fichier.tar.gz.gpg
r2_delete() {
  local key="$1"

  if [[ -z "$key" ]]; then
    echo "Usage : r2_delete <chemin_r2>" >&2
    return 1
  fi

  _r2_load_env || return 1

  local endpoint="https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
  local url="${endpoint}/${R2_BUCKET}/${key}"

  curl --silent --show-error --fail --request DELETE "$url" \
    --user "${R2_ACCESS_KEY_ID}:${R2_SECRET_ACCESS_KEY}" \
    --aws-sigv4 "aws:amz:auto:s3" || return 1
}

# ---------- CLI : exécution en script ----------
# Usage : ./curl_r2.sh upload <fichier_local> <chemin_r2>
#         ./curl_r2.sh download <chemin_r2> <fichier_local>
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    upload)
      r2_upload "${2:?Argument manquant: fichier local}" "${3:?Argument manquant: chemin R2}"
      ;;
    download)
      r2_download "${2:?Argument manquant: chemin R2}" "${3:?Argument manquant: fichier local}"
      ;;
    *)
      echo "Usage : $0 upload <fichier_local> <chemin_r2>"
      echo "        $0 download <chemin_r2> <fichier_local>"
      echo ""
      echo "Exemples :"
      echo "  $0 upload ./mon-fichier.txt backups/mon-fichier.txt"
      echo "  $0 download backups/mon-fichier.txt ./recupere.txt"
      exit 1
      ;;
  esac
fi