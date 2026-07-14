#!/bin/bash
# SFTP Entrypoint script to handle permissions and start the service

SFTP_USER=${SFTP_USER:-sftp_user}
SFTP_PASSWORD=${SFTP_PASSWORD:-password}
SFTP_UID=${SFTP_UID:-1001}

echo "Configuring permissions for SFTP user: $SFTP_USER"

# List of directories to manage permissions for
DIRS="objectstorage seaweedfs postgres-data clickhouse-data kafka-data db-backups clickhouse-backups"

for dir in $DIRS; do
    # ПЕРЕВІРКА: ми монтуємо в /home/sftp_user/, але користувач може мати інше ім'я.
    # SFTP образ створює домашню директорію для користувача.
    # Якщо SFTP_USER != sftp_user, то дані будуть в /home/sftp_user/, а користувач в /home/$SFTP_USER/
    # Тому краще перевіряти обидва шляхи або використовувати фіксований шлях для монтування.
    
    PATH_TO_DIR="/home/sftp_user/${dir}"
    if [ ! -d "$PATH_TO_DIR" ]; then
        PATH_TO_DIR="/home/${SFTP_USER}/${dir}"
    fi

    if [ -d "$PATH_TO_DIR" ]; then
        echo "Setting permissions for $PATH_TO_DIR"
        chown -R ${SFTP_UID}:${SFTP_UID} "$PATH_TO_DIR"
        chmod -R 777 "$PATH_TO_DIR"
    else
        echo "Directory $PATH_TO_DIR does not exist, skipping..."
    fi
done

echo "Starting SFTP server..."
# Call the original entrypoint with the user configuration
exec /entrypoint "${SFTP_USER}:${SFTP_PASSWORD}:${SFTP_UID}"
