#!/bin/bash

# Local MySQL root credentials for creating dumps (change these to your actual MySQL root credentials)
MYSQL_ROOT_USER="#"
MYSQL_ROOT_PASSWORD="#"

# Directory to store the MySQL dumps
DUMP_DIR="/home/mysql_dumps"

# Define the remote database host and port (fixed values)
REMOTE_MYSQL_HOST="88.223.84.185"
REMOTE_MYSQL_PORT="3306"  # Add the port here if it's not the default MySQL port

# Create the dump directory if it doesn't exist
mkdir -p "$DUMP_DIR"

# Function to extract database credentials from wp-config.php and create a MySQL dump using root credentials
create_mysql_dump() {
  local wp_config_path="$1"
  local site_name="$2"

  echo "Reading wp-config.php from $wp_config_path..."

  # Extract DB name from wp-config.php (trying more flexible approach)
  db_name=$(grep -oP "define\('DB_NAME',\s*['\"]([^'\"]+)['\"]\);" "$wp_config_path" | cut -d"'" -f2)

  # Debugging: Check if extraction failed and print the relevant part of wp-config.php
  if [[ -z "$db_name" ]]; then
    echo "Could not extract database name from $wp_config_path."
    echo "Checking the content of wp-config.php for DB_NAME..."

    # Print the relevant lines from wp-config.php for manual inspection
    grep "DB_NAME" "$wp_config_path"

    echo "Enter the database name manually for $site_name:"
    read -r db_name
  fi

  if [[ -n "$db_name" ]]; then
    echo "Creating MySQL dump for $site_name (DB: $db_name)..."

    # Create MySQL dump using local MySQL root credentials
    mysqldump -u"$MYSQL_ROOT_USER" -p"$MYSQL_ROOT_PASSWORD" "$db_name" > "$DUMP_DIR/${site_name}_$(date +%F).sql"

    if [[ $? -eq 0 ]]; then
      echo "MySQL dump created successfully for $site_name: $DUMP_DIR/${site_name}_$(date +%F).sql"
    else
      echo "Error creating MySQL dump for $site_name"
    fi
  else
    echo "No database name provided for $site_name. Skipping MySQL dump."
  fi
}

# Function to restore MySQL dump to a remote server
restore_mysql_dump() {
  local dump_file="$1"
  local site_name="$2"

  # Prompt for remote database details
  echo "Enter the remote database username for $site_name:"
  read -r remote_db_user
  echo "Enter the remote database password for $site_name:"
  read -r -s remote_db_password
  echo "Enter the remote database name for $site_name:"
  read -r remote_db_name

  echo "Restoring $dump_file to the remote database $remote_db_name at host $REMOTE_MYSQL_HOST..."

  # Perform the MySQL restore using the fixed host and port, and user-provided credentials
  mysql -u "$remote_db_user" -p"$remote_db_password" -h "$REMOTE_MYSQL_HOST" -P "$REMOTE_MYSQL_PORT" "$remote_db_name" < "$dump_file"

  if [[ $? -eq 0 ]]; then
    echo "MySQL dump restored successfully for $site_name"
  else
    echo "Error restoring MySQL dump for $site_name"
  fi
}

# Collect websites to transfer
declare -a websites
index=0

# Scan home directory for WordPress installations
for DOMAIN_DIR in /home/*; do
  DOMAIN=$(basename "$DOMAIN_DIR")
  
  # Skip specific directories
  if [[ "$DOMAIN" == "docker" || "$DOMAIN" == "vmail" || "$DOMAIN" == "cyberpanel" ]]; then
    continue
  fi

  # Check if wp-config.php exists
  WP_CONFIG_PATH="$DOMAIN_DIR/public_html/wp-config.php"
  if [[ -f "$WP_CONFIG_PATH" ]]; then
    websites+=("$DOMAIN")
    echo "$index: $DOMAIN"
    ((index++))
  fi
done

# Prompt user to select websites for MySQL dump
if [ ${#websites[@]} -eq 0 ]; then
  echo "No WordPress sites found in /home."
  exit 1
fi

echo "Please select the websites for which you want to create a MySQL dump (comma-separated numbers):"
read -r selection

# Convert the selection into an array
IFS=',' read -r -a selected_indices <<< "$selection"

# Process selected websites
for i in "${selected_indices[@]}"; do
  if [[ "$i" =~ ^[0-9]+$ ]] && [ "$i" -lt "${#websites[@]}" ]; then
    DOMAIN="${websites[$i]}"
    WP_CONFIG_PATH="/home/$DOMAIN/public_html/wp-config.php"

    # Check if wp-config.php exists and is readable
    if [[ -f "$WP_CONFIG_PATH" ]]; then
      # Create MySQL dump
      create_mysql_dump "$WP_CONFIG_PATH" "$DOMAIN"

      # Construct the dump file path
      dump_file="$DUMP_DIR/${DOMAIN}_$(date +%F).sql"

      # Call function to restore the MySQL dump to the remote server
      restore_mysql_dump "$dump_file" "$DOMAIN"
    else
      echo "wp-config.php not found or not readable for $DOMAIN."
    fi
  else
    echo "Invalid selection: $i"
  fi
done

echo "MySQL dump creation and restoration process completed."
