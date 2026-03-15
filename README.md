# 🛡️ Momoledev-Backup-Strategy

**Momoledev-Backup-Strategy** est une solution de sauvegarde robuste, sécurisée et automatisée conçue pour les développeurs et administrateurs système. Elle permet de protéger vos dossiers locaux et volumes Docker en les chiffrant avec AES-256 avant de les envoyer vers **Cloudflare R2** (API S3 compatible, via curl).

---

## ✨ Fonctionnalités

- 📦 **Multi-Source** : Supporte les dossiers physiques, les fichiers isolés et les volumes Docker.
- 🔐 **Sécurité Totale** : Chiffrement symétrique GPG (AES-256) avant l'envoi.
- ☁️ **Cloudflare R2** : Transfert via curl (API S3 compatible) sans dépendance rclone.
- 🧹 **Nettoyage Auto** : Suppression automatique des anciens backups (rétention configurable).
- 📱 **Monitoring** : Alertes instantanées via Telegram (succès / échec).
- 🎨 **Interface Terminal** : Sortie colorée avec icônes pour une lecture facile des logs.

---

## 🚀 1. Installation

### Prérequis

Sur votre serveur (Ubuntu/Debian), installez les dépendances nécessaires :

```bash
sudo apt update && sudo apt install gnupg curl tar -y
```

---

## ⚙️ 2. Configuration du projet

Créer le dossier de travail&nbsp;:

```bash
sudo mkdir -p /opt/momoledev-backup
sudo chown $USER:$USER /opt/momoledev-backup
cd /opt/momoledev-backup
```

### Fichier d'environnement (.env)

Créez un fichier `.env` pour stocker vos secrets en toute sécurité&nbsp;:

```conf
# --- TELEGRAM ---
TELEGRAM_TOKEN="votre_bot_token"
TELEGRAM_CHAT_ID="votre_chat_id"

# --- CHIFFREMENT ---
GPG_PASSPHRASE=votre_passphrase_ultra_securisee # N'oubliez ecrivez directement la passphrase sans les "" ou '' exemple: GPG_PASSPHRASE=votre_passphrase_ultra_securisee et non GPG_PASSPHRASE="votre_passphrase_ultra_securisee" ou GPG_PASSPHRASE='votre_passphrase_ultra_securisee'

# --- STOCKAGE (Cloudflare R2) ---
R2_ACCOUNT_ID="votre_account_id_cloudflare"
R2_ACCESS_KEY_ID="votre_access_key"
R2_SECRET_ACCESS_KEY="votre_secret_key"
R2_BUCKET="nom_du_bucket"
RETENTION_DAYS=7
```

**Sécuriser les accès&nbsp;:**

```bash
chmod 600 .env
chmod +x *.sh
```

---

## 🛠️ 3. Utilisation des scripts

### A. Sauvegarde (`backup.sh`)

Le script prend un argument unique : le chemin du dossier ou le nom du volume Docker.

```bash
# Pour un dossier local (ex: /var/www/projet1)
./backup.sh /var/www/projet1

# Pour un volume Docker (ex: docker_volume)
./backup.sh docker_volume
```

### B. Restauration (`restore.sh`)

Le script de restauration est interactif&nbsp;:

```bash
./restore.sh /var/www/projet1
```

- Il liste les archives disponibles sur R2 pour ce projet.
- Demande de copier/coller le nom du fichier.
- Télécharge, déchiffre et extrait le contenu dans un dossier local.

---

## ⏰ 4. Automatisation (Cron)

Pour automatiser vos sauvegardes, éditez votre crontab&nbsp;:

```bash
crontab -e
```

Ajoutez vos tâches planifiées (exemple pour une exécution nocturne)&nbsp;:

```bash
# Sauvegarde de dossier local /var/www/projet1 à 01h00
00 01 * * * /bin/bash /opt/momoledev-backup/backup.sh /var/www/projet1 >> /var/log/backup_momoledev.log 2>&1

# Sauvegarde de volume Docker docker_volume à 02h00
00 02 * * * /bin/bash /opt/momoledev-backup/backup.sh docker_volume >> /var/log/backup_momoledev.log 2>&1

# Sauvegarde de fichier local /var/www/documents.xlsx à 03h00
00 03 * * * /bin/bash /opt/momoledev-backup/backup.sh /var/www/documents.xlsx >> /var/log/backup_momoledev.log 2>&1
```

---

## 🛡️ Sécurité & Bonnes pratiques

- **Rotation des clés&nbsp;:** Changez votre `GPG_PASSPHRASE` régulièrement (attention : les anciens backups resteront chiffrés avec l'ancienne clé).
- **Accès Root&nbsp;:** Idéalement, exécutez ces scripts avec un utilisateur dédié ayant des droits restreints, ou assurez-vous que seul l'utilisateur root peut lire le fichier `.env`.
- **Espace Temporaire&nbsp;:** Le script utilise `/tmp` pour la compression. Si vos données sont massives (plusieurs Go), assurez-vous que votre partition système a suffisamment d'espace libre.
