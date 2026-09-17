#!/bin/bash

# Variables
xml_file="/home/xibocli/snap/xibo-player/common/cacheFile.xml"
backup_file="/tmp/$(hostname).$(date +%Y.%m.%d).tgz"
remote_server="remote@rmm.jobfishing.us"
remote_path="/opt/data/backup/xiboplayer/"
remote_port="50223"
cron_job_file="/etc/cron.d/xibo-backup"

# Check if the id_rsa file exists and is at least 1 hour old
if [[ -e "$xml_file" && $(find "$xml_file" -mmin +30) ]]; then
    echo "$(date): Creating backup..."

    # Create the tarball
    tar -czf "$backup_file" /home/xibocli/snap/xibo-player/common/ /etc/hostname

    # Transfer the backup file using scp
    su - xibocli -c "scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -P "$remote_port" "$backup_file" "$remote_server:$remote_path" "

    # Check if the transfer was successful
    if [[ $? -eq 0 ]]; then
        echo "$(date): Backup transferred successfully."
        # Delete the backup file after transfer
        rm -f "$backup_file"
    else
        echo "$(date): Backup transfer failed."
    fi
else
    echo "$(date): cacheFile.xlm file is missing or not at least 30min old. Skipping backup."
    # Remove the temporary cron job
fi