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
# Last Modified:   19/08/2026 - (support gemini)
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

set -o pipefail # Importante para capturar erros em pipelines

# Credenciais e Contatos
source /scripts/ENV # Deve conter as variáveis TELEGRAM_BOT_TOKEN e CHAT_ID
password_file="/scripts/password" # Arquivo com a senha do repositório Restic
email="admin@seudominio.com"

# Retenção do Backup (Restic)
keep_days="20"

# Discos e Pontos de Montagem
disco_dados="/mnt/Data"                  # Disco principal onde estão os dados de origem
midia_externa="/mnt/HD_Externo/Backups"  # Mídia principal de backup (HD Externo, NAS, etc)
restic_local="/mnt/BackupLocal/Restic"   # Repositório Restic local (Fallback)
restic_pen="/mnt/Pendrive/Restic"        # Mídia secundária de backup (Pendrive)

# Diretórios de Origem (O que será "backupeado")
backup_dir="$disco_dados/containers"
backup_dir1="$disco_dados/Documentos"

# Logs e Cache
log_file="/tmp/syncbackup_$(date +%Y%m%d_%H%M%S).log"
restic_cache_dir="$disco_dados/restic_cache"

# ==============================================================================
# FIM DAS CONFIGURAÇÕES - NÃO ALTERAR ABAIXO SALVO NECESSIDADE DE ADAPTAR LÓGICA
# ==============================================================================

docker_was_stopped=false
restic_check_status=0

# --- FUNÇÃO DE LIMPEZA (TRAP) ---
cleanup() {
    if $docker_was_stopped; then
        echo "$(date +'%H:%M:%S') - [🔄 TRAP] Reiniciando Docker após interrupção..." | tee -a "$log_file"
        systemctl start docker
    fi
}

trap cleanup EXIT ERR INT TERM

echo "-----------------------------------------------------" | tee "$log_file"
echo "Iniciando script de backup: $(date +'%d/%m/%Y %H:%M:%S')" | tee -a "$log_file"
echo "-----------------------------------------------------" | tee -a "$log_file"

# --- VERIFICAÇÃO CRÍTICA DO DISCO DE DADOS ---
# Evita que o cache ou o backup rodem se o disco principal não estiver montado
if ! mountpoint -q "$disco_dados"; then
    echo "$(date +'%H:%M:%S') - [🔴 FALHA CRÍTICA] Ponto de montagem $disco_dados não está acessível. Abortando para evitar backup vazio e gravação na raiz do sistema." | tee -a "$log_file"
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" -d chat_id="${CHAT_ID}" -d text="[🔴 FALHA CRÍTICA] Disco de dados ($disco_dados) desmontado em $(hostname). Backup abortado para proteger os dados!"
    exit 1
fi

# Cria diretório de cache fora do /tmp com segurança
mkdir -p "$restic_cache_dir"

# Verificar se o ponto de montagem principal está acessível
if touch "$midia_externa/.checkpoint_can_write" 2>/dev/null; then
    rm -f "$midia_externa/.checkpoint_can_write"
    echo "$(date +'%H:%M:%S') - [💾 INFO] Mídia externa $midia_externa acessível." | tee -a "$log_file"

    # --- Backup Restic Local ---
    echo "$(date +'%H:%M:%S') - [⏳ INFO] Iniciando backup Restic para $restic_local..." | tee -a "$log_file"
    restic -r "$restic_local" --cache-dir "$restic_cache_dir" --verbose --password-file "$password_file" backup "$backup_dir" "$backup_dir1" | tee -a "$log_file"
    restic_backup_status=$?
    
    if [[ $restic_backup_status -ne 0 ]]; then
        echo "$(date +'%H:%M:%S') - [❌ ERRO] Backup Restic local falhou!" | tee -a "$log_file"
    else
        echo "$(date +'%H:%M:%S') - [✅ INFO] Backup Restic local concluído. Verificando integridade..." | tee -a "$log_file"
        restic -r "$restic_local" --cache-dir "$restic_cache_dir" --password-file "$password_file" check | tee -a "$log_file"
        restic_check_status=$?
        
        if [[ $restic_check_status -ne 0 ]]; then
            echo "$(date +'%H:%M:%S') - [🔒 ERRO RESTIC] Verificação falhou em $(hostname). O repositório pode estar travado. Verifique com 'restic unlock'." | tee -a "$log_file"
            curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" -d chat_id="${CHAT_ID}" -d text="[🔒 ERRO RESTIC] Verificação falhou em $(hostname). O repositório pode estar travado. Verifique com 'restic unlock'."
        else
            echo "$(date +'%H:%M:%S') - [✅ INFO] Verificação Restic local concluída com sucesso." | tee -a "$log_file"
        fi
    fi
    sleep 5

    # --- Parar Docker para Sincronizações Críticas ---
    echo "$(date +'%H:%M:%S') - [🛑 INFO] Parando Docker..." | tee -a "$log_file"
    systemctl stop docker
    docker_was_stopped=true
    sleep 5

    # --- Sincronizar Restic Local para Mídias Externas ---
    echo "$(date +'%H:%M:%S') - [🔄 INFO] Sincronizando Restic local para $midia_externa/restic..." | tee -a "$log_file"
    rsync -ravz --timeout=60 --delete "$restic_local/" "$midia_externa/restic/" | tee -a "$log_file"
    rsync_midia_externa_status=$?

    # --- Sincronizar Restic Local para Pendrive ---
    if mountpoint -q "$(dirname "$restic_pen")" || [ -d "$restic_pen" ]; then
        echo "$(date +'%H:%M:%S') - [🔄 INFO] Sincronizando Restic local para $restic_pen..." | tee -a "$log_file"
        rsync -ravz --timeout=60 --delete "$restic_local/" "$restic_pen/" | tee -a "$log_file"
        rsync_pen_status=$?
    else
        echo "$(date +'%H:%M:%S') - [⚠️ ATENÇÃO] Pendrive não detectado ou montado. Pulando sincronização do pen drive." | tee -a "$log_file"
        rsync_pen_status=0
    fi

    # --- Forget e Prune no Restic Local ---
    if [[ $rsync_midia_externa_status -eq 0 && $rsync_pen_status -eq 0 && $restic_check_status -eq 0 ]]; then
        echo "$(date +'%H:%M:%S') - [🧹 INFO] Sincronizações e Verificações OK. Executando forget e prune no local." | tee -a "$log_file"
        restic forget --cache-dir "$restic_cache_dir" --password-file "$password_file" --keep-last "$keep_days" -r "$restic_local" | tee -a "$log_file"
        restic prune --cache-dir "$restic_cache_dir" -r "$restic_local" --password-file "$password_file" | tee -a "$log_file"
    else
        echo "$(date +'%H:%M:%S') - [⚠️ ATENÇÃO] Falha em alguma etapa (Sync ou Check Restic). Forget e Prune não executados no repositório local por segurança." | tee -a "$log_file"
    fi

    # --- Sincronizar outros dados (Raw Files) ---
    echo "$(date +'%H:%M:%S') - [🔄 INFO] Sincronizando $backup_dir e $backup_dir1 para $midia_externa/dados_sync..." | tee -a "$log_file"
    rsync -razv --timeout=60 "$backup_dir/" "$backup_dir1/" "$midia_externa/dados_sync/" | tee -a "$log_file"
    rsync_containers_status=$?

    # --- Reiniciar Docker ---
    echo "$(date +'%H:%M:%S') - [▶️ INFO] Iniciando Docker..." | tee -a "$log_file"
    systemctl start docker
    docker_was_stopped=false
    docker ps | tee -a "$log_file"

    # --- Backup vnstat ---
    echo "$(date +'%H:%M:%S') - [📊 INFO] Executando backup vnstat para $midia_externa/vnstat_sync..." | tee -a "$log_file"
    vnstat_log_temp="/tmp/bkpvnstat_$(date +%Y%m%d_%H%M%S).log"
    rsync -ravz --timeout=60 /var/lib/vnstat "$midia_externa/vnstat_sync/" | tee "$vnstat_log_temp"
    rsync_vnstat_status=$?
    cat "$vnstat_log_temp" >> "$log_file"

    if [[ $rsync_vnstat_status -ne 0 ]]; then
        echo "$(date +'%H:%M:%S') - [❌ ERRO] Falha no backup do vnstat." | tee -a "$log_file"
        echo -e "$(date +'%d/%m/%Y %H:%M') - Assunto: Falha no backup do vnstat para $midia_externa no $(hostname)" | /usr/bin/mail -s "[Backup Falhou] vnstat em $(hostname)" "$email"
    fi

    # --- Notificação Final de Sucesso ---
    if [[ $restic_backup_status -eq 0 && $restic_check_status -eq 0 && $rsync_midia_externa_status -eq 0 && $rsync_pen_status -eq 0 && $rsync_containers_status -eq 0 && $rsync_vnstat_status -eq 0 ]]; then
        echo "$(date +'%H:%M:%S') - [✅ Sucesso] Backup em $(hostname) para $midia_externa e $restic_pen concluído." | tee -a "$log_file"
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" -d chat_id="${CHAT_ID}" -d text="[✅ Sucesso] Backup em $(hostname) para $midia_externa e $restic_pen concluído. $(date +"%H:%M:%S - %d/%m/%Y")"
    else
        echo "$(date +'%H:%M:%S') - [⚠️ Falha Parcial] Backup em $(hostname) teve problemas. Verifique os logs." | tee -a "$log_file"
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" -d chat_id="${CHAT_ID}" -d text="[⚠️ Falha Parcial] Backup em $(hostname) teve problemas. Verifique os logs. $(date +"%H:%M:%S - %d/%m/%Y")"
    fi

else
    # --- Mídia Externa NÃO Acessível ---
    echo "$(date +'%H:%M:%S') - [🔴 FALHA MÍDIA] Ponto de montagem $midia_externa em $(hostname) nao acessivel. Tentando backup local Restic..." | tee -a "$log_file"
    echo -e "$(date +'%d/%m/%Y %H:%M') - Assunto: Ponto de montagem $midia_externa nao acessível no $(hostname)" | /usr/bin/mail -s "[Backup Falhou] Mídia Externa $(hostname)" "$email"
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" -d chat_id="${CHAT_ID}" -d text="[🔴 FALHA MÍDIA] Ponto de montagem $midia_externa em $(hostname) nao acessivel. Tentando backup local Restic..."

    echo "$(date +'%H:%M:%S') - [⏳ INFO] Iniciando backup Restic APENAS para $restic_local..." | tee -a "$log_file"
    restic -r "$restic_local" --cache-dir "$restic_cache_dir" --verbose --password-file "$password_file" backup "$backup_dir" "$backup_dir1" | tee -a "$log_file"
    
    if [[ $? -eq 0 ]]; then
        echo "$(date +'%H:%M:%S') - [⚠️ Backup Local] Mídia externa inacessível em $(hostname). Backup Restic local feito." | tee -a "$log_file"
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" -d chat_id="${CHAT_ID}" -d text="[⚠️ Backup Local] Mídia externa inacessível em $(hostname). Backup Restic local feito. $(date +"%H:%M:%S - %d/%m/%Y")"
    else
        echo "$(date +'%H:%M:%S') - [🔴 FALHA TOTAL] Mídia externa E backup Restic local falharam em $(hostname)." | tee -a "$log_file"
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" -d chat_id="${CHAT_ID}" -d text="[🔴 FALHA TOTAL] Mídia externa E backup Restic local falharam em $(hostname). $(date +"%H:%M:%S - %d/%m/%Y")"
    fi
fi

# --- Garantir que o Docker seja iniciado ---
if ! systemctl is-active --quiet docker; then
    echo "$(date +'%H:%M:%S') - [▶️ INFO] Docker não está ativo. Tentando iniciar (salvaguarda final)..." | tee -a "$log_file"
    systemctl start docker
    docker ps | tee -a "$log_file"
fi

echo "-----------------------------------------------------" | tee -a "$log_file"
echo "Script de backup finalizado: $(date +'%d/%m/%Y %H:%M:%S')" | tee -a "$log_file"
echo "Log completo em: $log_file"
echo "-----------------------------------------------------" | tee -a "$log_file"

docker ps 
exit 0
