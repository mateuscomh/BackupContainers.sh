#!/bin/bash

source /scripts/ENV
ponto_montagem="/mnt"
restic_local="/mnt/Restic
restic_pen_morpheus="/mnt/ResticBackup"
password_file="/scripts/password"
email=""
remote_user=""
remote_host="xxxx"
remote_port="xxx"
backup_dir="/mnt/Data/containers"
backup_dir1="/mnt/Data/obs"
log_file="/tmp/syncbackup"

# Backup de midia com Restic
  restic -r "$restic_local" --verbose --password-file "$password_file" backup "$backup_dir" | tee $log_file
  restic -r "$restic_local" --password-file "$password_file" check | tee -a "$log_file"
  restic forget --password-file "$password_file" --keep-last 10 -r "$restic_local" | tee -a "$log_file"
  restic prune -r "$restic_local" --password-file "$password_file" | tee -a "$log_file"

# Verificar se o ponto de montagem remoto está acessível
ssh -p $remote_port $remote_user@$remote_host "test -d $ponto_montagem"
if [[ $? -eq 0 ]]; then
  # Se o ponto de montagem estiver acessível, parar o Docker
  systemctl stop docker

  # Executar o rsync
  rsync -Crazv -e "ssh -p $remote_port" "$restic_local" "$remote_user@$remote_host:$restic_pen_morpheus" | tee -a $log_file
  rsync -Crazv -e "ssh -p $remote_port" "$backup_dir" "$backup_dir1" "$remote_user@$remote_host:$ponto_montagem/containersBlade" | tee -a $log_file
  date +"%H:%M:%S - %d/%m/%Y" | tee -a $log_file

  # Verificar se o rsync foi bem-sucedido
  if [[ $? -ne 0 ]]; then
    # Enviar e-mail se o rsync falhar
    echo -e "$(date +'%d/%m/%Y %H:%M') - Assunto: Ponto de montagem $ponto_montagem nao montado" | /usr/bin/mail -s "Ponto de montagem não está pronto" "$email"
    sleep 5

    # Executar backup vnstat
    rsync -Cravz -e "ssh -p $remote_port" /var/lib/vnstat "$remote_user@$remote_host:$ponto_montagem/vnstatBlade" | tee /tmp/bkpvnstat
    date +"%H:%M:%S - %d/%m/%Y" >> /tmp/bkpvnstat
    sleep 15
    # Reiniciar o Docker
    systemctl start docker
    docker ps
  fi

else
  # Enviar e-mail se o ponto de montagem remoto não estiver acessível
  echo -e "$(date +'%d/%m/%Y %H:%M') - Assunto: Ponto de montagem $ponto_montagem nao acessível" | /usr/bin/mail -s "Ponto de montagem não está acessível" "$email" | tee "$log_file"
  curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" -d chat_id="${CHAT_ID}" -d text="[🔴 Down] Ponto de montagem $ponto_montagem nao acessivel"
  date +"%H:%M:%S - %d/%m/%Y" | tee -a "$log_file"
  restic -r "$restic_local" --verbose --password-file "$password_file" backup "$backup_dir" | tee -a "$log_file"
fi

# Reiniciar o Docker
systemctl start docker
docker ps

exit
