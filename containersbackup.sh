#!/bin/bash
# ----------------------------------------------------------------------------
# Script Name:     backup_script.sh
# Description:     This script automates the process of backing up containers 
#                  and directories using Restic and Rsync. It stops Docker 
#                  during the backup process and restarts it after completion. 
#                  Notifications are sent via email and Telegram in case of errors.
# 
# Author:          Matheus Martins
# Created:         Out-24
# Last Modified:   07/10/2024
# Version:         1.1
# ----------------------------------------------------------------------------
# Requirements:
#   - Restic (for creating and managing backups)
#   - Rsync (for synchronizing data to remote server)
#   - Docker (manages containers, stops and restarts during backup)
#   - SSH (for secure connections to remote server)
#   - Mailutils (for sending email notifications)
#   - Curl (for sending Telegram notifications)
#
# Usage:
#   Run this script manually or schedule it using cron for automated backups.
# ----------------------------------------------------------------------------


source /scripts/ENV
ponto_montagem="/path/to/mount/point/"
restic_local="/path/to/restic/folder"
restic_pen_remote="/path/to/restic/remote"
password_file="/path/to/passwordpassword"
email="local-user"
remote_user="remote-user"
remote_host="x.x.x.x"
remote_port="xxx"
backup_dir="/path/to/backup/folder"
backup_dir1="/path/to/backup2/folder"
log_file="/tmp/backupcontainer.log"

# Media Backup Restic
  restic -r "$restic_local" --verbose --password-file "$password_file" backup "$backup_dir" | tee $log_file
  restic -r "$restic_local" --password-file "$password_file" check | tee -a "$log_file"
  restic forget --password-file "$password_file" --keep-last 10 -r "$restic_local" | tee -a "$log_file"
  restic prune -r "$restic_local" --password-file "$password_file" | tee -a "$log_file"

# Check mount point
ssh -p $remote_port $remote_user@$remote_host "test -d $ponto_montagem"
if [[ $? -eq 0 ]]; then
  systemctl stop docker
  
  rsync -Crazv -e "ssh -p $remote_port" "$restic_local" "$remote_user@$remote_host:$restic_pen_morpheus" | tee -a $log_file
  rsync -Crazv -e "ssh -p $remote_port" "$backup_dir" "$backup_dir1" "$remote_user@$remote_host:$ponto_montagem/containersBlade" | tee -a $log_file
  date +"%H:%M:%S - %d/%m/%Y" | tee -a $log_file

  if [[ $? -ne 0 ]]; then
    echo -e "$(date +'%d/%m/%Y %H:%M') - Assunto: Ponto de montagem $ponto_montagem nao montado" | /usr/bin/mail -s "Ponto de montagem não está pronto" "$email"
    sleep 3

    rsync -Cravz -e "ssh -p $remote_port" /var/lib/vnstat "$remote_user@$remote_host:$ponto_montagem/vnstatBlade" | tee /tmp/bkpvnstat
    date +"%H:%M:%S - %d/%m/%Y" >> /tmp/bkpvnstat
    sleep 15

    systemctl start docker
    docker ps
  fi
  else
    echo -e "$(date +'%d/%m/%Y %H:%M') - Assunto: Ponto de montagem $ponto_montagem nao acessível" | /usr/bin/mail -s "Ponto de montagem não está acessível" "$email" | tee "$log_file"
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" -d chat_id="${CHAT_ID}" -d text="[🔴 Down] Ponto de montagem $ponto_montagem nao acessivel"
    date +"%H:%M:%S - %d/%m/%Y" | tee -a "$log_file"
    restic -r "$restic_local" --verbose --password-file "$password_file" backup "$backup_dir" | tee -a "$log_file"
fi

systemctl start docker
docker ps

exit
