## Description
This script automates the backup process for containers and other important directories using Restic and Rsync. It also sends email and Telegram notifications in case of failures. The script manages the Docker service, stopping it before the backup and restarting it after completion.

## Features

- Performs local backups with **Restic**.
- Checks the integrity of local backups and performs maintenance (prune).
- Syncs backups to a remote server via **Rsync**.
- Stops Docker during the backup and restarts the service after.
- Sends email and Telegram notifications in case of remote mount point failures.
- Backs up network statistics from **vnstat**.
- Flexible to adapt to different scenarios and directories.

## Requirements

- **Restic**: Backup tool used to create and manage snapshots.
- **Rsync**: Used to sync with the remote server.
- **Docker**: Service managed during the backup process.
- **SSH**: Secure connection between the local and remote servers.
- **Mailutils**: For sending email notifications.
- **Curl**: Used for integration with the Telegram API.

## Setup

1. Clone this repository or copy the script to your environment.
2. Define your environment variables in the `/scripts/ENV` file:
   - `TELEGRAM_BOT_TOKEN`: Your Telegram bot token.
   - `CHAT_ID`: Chat ID to which notifications will be sent.
3. Set up the `/scripts/password` file with the password used by Restic.
4. Adjust the paths for the `ponto_montagem`, `restic_local`, `restic_pen_morpheus`, `backup_dir`, and `backup_dir1` variables to the directories you want to use.
5. Configure SSH access to the remote server, ensuring the correct keys are in place and the remote user is authorized.
6. Set up email notifications by configuring the `email` variable.

## Usage

Run the script manually or set up a **cron job** to automate the backup at regular intervals:

```bash
crontab -e
```
Adjust and add this line
```bash
0 2 * * * /path/to/backup_script.sh
```

## Script Structure
- Backup with Restic: Creates backups and retains only the last 10 snapshots.
- Rsync Synchronization: Syncs local backups with the remote server, checking if the remote mount point is accessible.
- Docker Management: Stops Docker during the backup and restarts it afterward.
- Notifications: Sends emails and Telegram messages if any errors occur or the remote mount point is unavailable.

## Contributions
Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.

