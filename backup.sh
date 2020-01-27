#!/usr/bin/env bash

failed=0

# =============== SETTINGS ===============
# Some non secret settings.
REMOTE_BACKUP_HOST="backups"
REMOTE_BACKUP_PATH="./borg/$(hostname)"
# For less noise in the logs this is a static folder instead of a tmp one.
LOCAL_BACKUP_STORAGE="$HOME/automatic-backups"
# Keep a week's worth of logs.
LOG="/var/log/backup-$(LC_TIME=en_US.UTF-8 date +%A).log"
# Thanks https://stackoverflow.com/a/246128
DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)
# The scripts are stored next to this file.
SCRIPTS_DIR="${DIR}/scripts"
# Load secret settings form secrets.env next to this file
# shellcheck disable=SC2046 # We want wordsplitting here.
export $(grep -Ev '^#' "${DIR}/secrets.env" | xargs)
# =============== SETTINGS ===============

# Helpers and error handling
shopt -s expand_aliases
alias logdate="date '+%F %T'"
info() { printf "\e[1;32mINFO [%s] %s\e[0m\n" "$(logdate)" "$*"; }
warn() { printf "\e[1;33mWARN [%s] %s\e[0m\n" "$(logdate)" "$*"; }
error() { failed=1; printf "\e[1;31mERROR [%s] %s\e[0m\n" "$(logdate)" "$*"; exit 2; }

# Cleanup
_interrupted() { error "Backup interrupted!"; exit 2; }
_exit() {
  # Send mail if something went wrong.
  if [ $failed -ne 0 ]; then
    warn "Something went wrong during the backup. Sending an email to $EMAIL_RECIPIENTS"
    mail -a "$LOG" -s "Backup failed on $(hostname)!" "$EMAIL_RECIPIENTS" <<EOF
An automatic backup has failed.
Please review the attached log.
Hostname: $(hostname)
Date: $(logdate)
EOF
  fi
  info "Deleting temp storage...";
  rm -r "$LOCAL_BACKUP_STORAGE";
  info "Done.";
}

trap _interrupted INT TERM
trap _exit EXIT

umask 077 || error "Error setting umask to 077"

# Redirect current script to log file ASAP
exec > >(tee -i "${LOG}" || error "Cannot open log file!")
exec 2>&1

# BORG_PASSPHRASE must be set.
[ -z "$BORG_PASSPHRASE" ] && error "BORG_PASSPHRASE must be set!"

info "Running backup scripts..."

[ ! -d "$LOCAL_BACKUP_STORAGE" ] && mkdir -p "$LOCAL_BACKUP_STORAGE"
cd "$LOCAL_BACKUP_STORAGE" || error "Could not CD into $LOCAL_BACKUP_STORAGE."

chmod 700 "$LOCAL_BACKUP_STORAGE"  || error "Error chowning $LOCAL_BACKUP_STORAGE to 700"

# Fast exclude root folders recursivly.
PATTERNS="--patterns-from defaults1.lst"
cat > defaults1.lst <<EOF
P sh
R /
! /lost+found
! /dev
! /proc
! /sys
! /tmp
! /run
! /mnt
! /media
! /var/cache
! ${LOCAL_BACKUP_STORAGE}
- /swapfile
EOF

# Run all the scripts
for f in "$SCRIPTS_DIR"/*; do
  if [ ! -x "$f" ]; then
    warn "Skipped $f, not executable."
  else
    info "Running $f"
    PATERN_FILE=$(mktemp -p "$LOCAL_BACKUP_STORAGE" XXXXXX.lst)
    # Read every line outputted from the script, the script must print what it wants backed up.
    # 120 sec timeout + kill after 25 seconds if not stopped.
    timeout -k 25 120 "$f" "$PATERN_FILE"
    code=$?
    if [ $code -ne 0 ]; then
      warn "Script failed with code: $code."
      failed=1
    fi
    info "Patterns:"
    cat "$PATERN_FILE"
    PATTERNS="$PATTERNS --patterns-from $PATERN_FILE"
  fi
done

# Now add a default case that makes it so only things included in the patterns will be included.
PATTERNS="$PATTERNS --patterns-from defaults2.lst"
cat > defaults2.lst <<EOF
P sh
R /
- /
EOF

info "Creating borg archive..."

export BORG_REPO="ssh://${REMOTE_BACKUP_HOST}/${REMOTE_BACKUP_PATH}"
## Archive prefix is hostname, this helps with filtering.
# shellcheck disable=SC2086
if ! borg create --verbose --list --stats --show-rc --filter AME --compression zstd ::'{hostname}-{now}' $PATTERNS; then
  warn "Error creating borg archive."
  failed=1
fi

info "Pruning old borg archives..."

if ! borg prune --verbose --list --stats --show-rc --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prefix '{hostname}-'; then
  warn "Error Pruning borg archives."
  failed=1
fi

info "Borg status info"

borg info

info "Backup complete!"
