#!/bin/bash

# Define remote server details
REMOTE_USER="#"
REMOTE_HOST="#"
REMOTE_PORT="#"
PASSWORD="#"  # Replace with your SSH password

# Define the base path on the remote server where the contents will be transferred
REMOTE_BASE_PATH="/home/u364637143/domains"

# Function to update database credentials in wp-config.php
update_db_credentials() {
  local remote_config_path="$1"
  local db_name="$2"
  local db_user="$3"
  local db_password="$4"

  echo "Updating database credentials in $remote_config_path on the remote server..."

  sshpass -p "$PASSWORD" ssh -p "$REMOTE_PORT" -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" \
  "sed -i \"s/define('DB_NAME', .*/define('DB_NAME', '$db_name');/\" '$remote_config_path'; \
   sed -i \"s/define('DB_USER', .*/define('DB_USER', '$db_user');/\" '$remote_config_path'; \
   sed -i \"s/define('DB_PASSWORD', .*/define('DB_PASSWORD', '$db_password');/\" '$remote_config_path';"

  echo "Database credentials updated successfully in $remote_config_path."
}

# Collect websites to transfer
declare -a websites
index=0

# Scan home directory for websites
for DOMAIN_DIR in /home/*; do
  DOMAIN=$(basename "$DOMAIN_DIR")

  # Skip specific folders
  if [[ "$DOMAIN" == "docker" || "$DOMAIN" == "vmail" || "$DOMAIN" == "cyberpanel" ]]; then
    continue
  fi

  # Check if public_html exists
  if [ -d "$DOMAIN_DIR/public_html" ]; then
    websites+=("$DOMAIN")
    echo "$index: $DOMAIN"
    ((index++))
  fi
done

# Prompt user for selection
echo "Enter the numbers of the websites you want to transfer (comma-separated):"
read -r selected_indices

# Convert the input to an array
IFS=',' read -r -a selected_array <<< "$selected_indices"

# Loop through selected websites
for i in "${selected_array[@]}"; do
  DOMAIN=${websites[$i]}
  DOMAIN_DIR="/home/$DOMAIN"

  # Transfer the contents of the public_html folder
  echo "Transferring contents of $DOMAIN_DIR/public_html to the remote server..."
  sshpass -p "$PASSWORD" rsync -avz -e "ssh -p $REMOTE_PORT -o StrictHostKeyChecking=no" "$DOMAIN_DIR/public_html/" "$REMOTE_USER@$REMOTE_HOST:$REMOTE_BASE_PATH/$DOMAIN/public_html/"

  if [[ $? -eq 0 ]]; then
    echo "Transfer complete for $DOMAIN."
  else
    echo "Transfer failed for $DOMAIN."
    continue  # Skip to the next domain if transfer fails
  fi

  # Construct the path to wp-config.php
  WP_CONFIG_PATH="$REMOTE_BASE_PATH/$DOMAIN/public_html/wp-config.php"

  # Prompt for new database credentials
  echo "Enter new database name for $DOMAIN:"
  read -r new_db_name
  echo "Enter new database username for $DOMAIN:"
  read -r new_db_user
  echo "Enter new database password for $DOMAIN:"
  read -r new_db_password

  # Update database credentials
  update_db_credentials "$WP_CONFIG_PATH" "$new_db_name" "$new_db_user" "$new_db_password"
done
