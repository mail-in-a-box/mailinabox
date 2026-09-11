#!/bin/bash

# migrate-miab.sh - Mail-in-a-Box Migration Script
# Author: Ahmad Kouider
# Created: April 3, 2025
# Description: Transfers Mail-in-a-Box data from one server to another
#
# Usage: ./migrate-miab.sh --username USER --target-host HOST --new-ip IP [OPTIONS]
#
# Required:
#   --username USER       SSH username for target server
#   --target-host HOST    IP address or domain of target server
#   --new-ip IP           Public IP address of the new target machine
#
# Options:
#   --source-path PATH    Path to Mail-in-a-Box files (default: /home/user-data)
#   --target-path PATH    Destination path on target server (default: /home/user-data)
#   --config-path PATH    Path to mailinabox.conf file (default: /etc/mailinabox.conf)
#   --exclude LIST        Comma-separated list of files/folders to exclude
#   --ssh-port PORT       SSH port to use (default: 22)
#   --stop-services       Stop Mail-in-a-Box services during transfer (default: keep running)
#   --ignore-partial      Continue migration even if some files fail to transfer (rsync code 23)
#   --dry-run             Simulate the transfer without making changes
#   --help                Display help message
#
# Example: ./migrate-miab.sh --username admin --target-host 192.168.1.100 --new-ip 203.0.113.10
#
# Note: After migration, you MUST reinstall Mail-in-a-Box on the target server:
#       curl -s https://mailinabox.email/setup.sh | sudo bash

# Default values
SOURCE_PATH="/home/user-data"
TARGET_PATH="/home/user-data"
EXCLUDE=""
DRY_RUN=false
STOP_SERVICES=false
SERVICES_STOPPED=false
IGNORE_PARTIAL=false
SSH_KEY_PATH="/tmp/miab_migration_key"
SSH_PORT=22
CONFIG_PATH="/etc/mailinabox.conf"

# Mail-in-a-Box services
MIAB_SERVICES=(
    "nginx"
    "dovecot"
    "postfix"
    "opendkim"
    "spamassassin"
    "postgrey"
    "clamav-daemon"
    "clamav-freshclam"
    "fail2ban"
    "nsd"
    "php8.1-fpm"
    "redis-server"
    "memcached"
    "rspamd"
    "unattended-upgrades"
    "mailinabox-daemon"
)

# Text formatting
BOLD="\033[1m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
NC="\033[0m" # No Color

# Function to display usage information
function show_usage {
    echo -e "${BOLD}Mail-in-a-Box Migration Script${NC}"
    echo -e "Transfers Mail-in-a-Box data from one server to another"
    echo ""
    echo -e "${BOLD}Usage:${NC}"
    echo "  $0 [options]"
    echo ""
    echo -e "${BOLD}Options:${NC}"
    echo "  --username USERNAME      SSH username for target server (required)"
    echo "  --target-host HOST      IP address or domain of target server (required)"
    echo "  --source-path PATH      Path to Mail-in-a-Box files (default: /home/user-data)"
    echo "  --target-path PATH      Destination path on target server (default: /home/user-data)"
    echo "  --config-path PATH      Path to mailinabox.conf file (default: /etc/mailinabox.conf)"
    echo "  --exclude LIST          Comma-separated list of files/folders to exclude"
    echo "  --new-ip IP             Public IP address of the new target machine (required)"
    echo "  --ssh-port PORT         SSH port to use (default: 22)"
    echo "  --stop-services         Stop Mail-in-a-Box services during transfer (default: keep running)"
    echo "  --ignore-partial       Continue migration even if some files fail to transfer (rsync code 23)"
    echo "  --dry-run               Simulate the transfer without making changes"
    echo "  --help                  Display this help message"
    echo ""
    echo -e "${BOLD}Example:${NC}"
    echo "  $0 --username admin --target-host 192.168.1.100 --new-ip 203.0.113.10 --exclude 'backup,logs'"
    exit 1
}

# Function to check if a command exists
function command_exists {
    command -v "$1" >/dev/null 2>&1
}

# Function to check required dependencies
function check_dependencies {
    local missing_deps=false
    
    if ! command_exists rsync; then
        echo -e "${RED}Error: rsync is not installed. Please install it and try again.${NC}"
        missing_deps=true
    fi
    
    if ! command_exists ssh; then
        echo -e "${RED}Error: ssh is not installed. Please install it and try again.${NC}"
        missing_deps=true
    fi
    
    if ! command_exists ssh-keygen; then
        echo -e "${RED}Error: ssh-keygen is not installed. Please install it and try again.${NC}"
        missing_deps=true
    fi
    
    if [ "$missing_deps" = true ]; then
        exit 1
    fi
}

# Function to validate IP address
function validate_ip {
    local ip=$1
    local stat=1
    
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IFS='.' read -r -a ip_segments <<< "$ip"
        [[ ${ip_segments[0]} -le 255 && ${ip_segments[1]} -le 255 && \
           ${ip_segments[2]} -le 255 && ${ip_segments[3]} -le 255 ]]
        stat=$?
    fi
    
    return $stat
}

# Function to generate SSH key pair
function generate_ssh_key {
    echo -e "\n${YELLOW}Generating temporary SSH key pair for migration...${NC}"
    
    # Remove old keys if they exist
    rm -f "${SSH_KEY_PATH}" "${SSH_KEY_PATH}.pub"
    
    # Generate new key pair without passphrase
    ssh-keygen -t ed25519 -f "${SSH_KEY_PATH}" -N "" -C "miab_migration_$(date +%Y%m%d)" >/dev/null 2>&1
    
    echo -e "\n${GREEN}SSH key pair generated successfully.${NC}"
    echo -e "\n${BOLD}Please add the following public key to ~/.ssh/authorized_keys on the target server:${NC}"
    echo -e "\n${YELLOW}$(cat "${SSH_KEY_PATH}.pub")${NC}\n"
}

# Function to test SSH connection
function test_ssh_connection {
    echo -e "${YELLOW}Testing SSH connection to $USERNAME@$TARGET_HOST...${NC}"
    
    if ssh -o BatchMode=yes -o ConnectTimeout=5 -p "$SSH_PORT" -i "${SSH_KEY_PATH}" "$USERNAME@$TARGET_HOST" exit >/dev/null 2>&1; then
        echo -e "${GREEN}SSH connection successful.${NC}"
        return 0
    else
        echo -e "${RED}SSH connection failed. Please ensure the public key is added to authorized_keys on the target server.${NC}"
        return 1
    fi
}

# Function to sync files using rsync
function sync_files {
    local rsync_options="-avz --progress"
    local exclude_options=""
    
    # Add trailing slash to source path if not present
    [[ "$SOURCE_PATH" != */ ]] && SOURCE_PATH="${SOURCE_PATH}/"
    
    # Process exclude list
    if [ -n "$EXCLUDE" ]; then
        IFS=',' read -ra EXCLUDE_ARRAY <<< "$EXCLUDE"
        for item in "${EXCLUDE_ARRAY[@]}"; do
            exclude_options="$exclude_options --exclude='$item'"
        done
    fi
    
    # Add dry-run option if specified
    if [ "$DRY_RUN" = true ]; then
        rsync_options="$rsync_options --dry-run"
        echo -e "\n${YELLOW}Running in DRY RUN mode. No files will be transferred.${NC}"
    fi
    
    echo -e "\n${YELLOW}Starting file synchronization...${NC}"
    echo -e "From: $SOURCE_PATH"
    echo -e "To: $USERNAME@$TARGET_HOST:$TARGET_PATH"
    
    # Execute rsync command
    eval rsync $rsync_options $exclude_options -e "ssh -p $SSH_PORT -i ${SSH_KEY_PATH}" "$SOURCE_PATH" "$USERNAME@$TARGET_HOST:$TARGET_PATH"
    local rsync_result=$?
    
    if [ $rsync_result -eq 0 ]; then
        echo -e "\n${GREEN}File synchronization completed successfully.${NC}"
        return 0
    elif [ $rsync_result -eq 23 ]; then
        # Error code 23 means partial transfer - some files were not transferred
        # but the overall transfer was mostly successful
        echo -e "\n${YELLOW}Warning: Partial file synchronization (code 23).${NC}"
        echo -e "${YELLOW}Some files or attributes were not transferred, but most files were synchronized successfully.${NC}"
        echo -e "${YELLOW}This is often due to permission issues, open files, or special files that cannot be transferred.${NC}"
        echo -e "${YELLOW}Would you like to continue with the migration? (y/n)${NC}"
        read -p "Continue? (y/n): " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${GREEN}Continuing with migration despite partial transfer...${NC}"
            return 0
        else
            echo -e "${RED}Migration aborted due to partial transfer.${NC}"
            return 1
        fi
    else
        echo -e "\n${RED}File synchronization failed with exit code $rsync_result.${NC}"
        return 1
    fi
}

# Function to update mailinabox.conf file
function update_mailinabox_conf {
    local temp_conf="/tmp/mailinabox.conf.tmp"
    local source_conf="${CONFIG_PATH}"
    
    echo -e "\n${YELLOW}Updating mailinabox.conf with new IP address...${NC}"
    
    # Check if mailinabox.conf exists
    if [ ! -f "$source_conf" ]; then
        echo -e "${RED}Error: mailinabox.conf not found at $source_conf${NC}"
        echo -e "${YELLOW}You can specify the correct path using --config-path option${NC}"
        return 1
    fi
    
    # Create a temporary copy of the config file
    if ! cp "$source_conf" "$temp_conf"; then
        echo -e "${RED}Error: Failed to create temporary copy of mailinabox.conf${NC}"
        return 1
    fi
    
    # Update the PUBLIC_IP value
    if ! sed -i "s/^PUBLIC_IP=.*/PUBLIC_IP=$NEW_IP/" "$temp_conf"; then
        echo -e "${RED}Error: Failed to update PUBLIC_IP in mailinabox.conf${NC}"
        rm -f "$temp_conf"
        return 1
    fi
    
    echo -e "${GREEN}mailinabox.conf updated locally.${NC}"
    
    # Transfer the updated config file to the target server
    if [ "$DRY_RUN" = false ]; then
        if ! scp -P "$SSH_PORT" -i "${SSH_KEY_PATH}" "$temp_conf" "$USERNAME@$TARGET_HOST:$CONFIG_PATH"; then
            echo -e "${RED}Failed to transfer updated mailinabox.conf to target server.${NC}"
            rm -f "$temp_conf"
            return 1
        fi
        
        echo -e "${GREEN}Updated mailinabox.conf transferred to target server.${NC}"
    else
        echo -e "${YELLOW}DRY RUN: Would transfer updated mailinabox.conf to target server.${NC}"
    fi
    
    # Clean up temporary file
    rm -f "$temp_conf"
    return 0
}

# Function to stop Mail-in-a-Box services
function stop_miab_services {
    echo -e "\n${YELLOW}Stopping Mail-in-a-Box services on source server...${NC}"
    local failed_services=""
    
    for service in "${MIAB_SERVICES[@]}"; do
        echo -e "Stopping $service..."
        if ! systemctl stop "$service" 2>/dev/null; then
            echo -e "${YELLOW}Warning: Failed to stop $service${NC}"
            failed_services="$failed_services $service"
        fi
    done
    
    if [ -z "$failed_services" ]; then
        echo -e "${GREEN}All Mail-in-a-Box services stopped successfully.${NC}"
        SERVICES_STOPPED=true
        return 0
    else
        echo -e "${YELLOW}Warning: Failed to stop some services:${NC}$failed_services"
        echo -e "${YELLOW}Continuing anyway...${NC}"
        SERVICES_STOPPED=true
        return 0
    fi
}

# Function to start Mail-in-a-Box services
function start_miab_services {
    echo -e "\n${YELLOW}Starting Mail-in-a-Box services on source server...${NC}"
    local failed_services=""
    
    for service in "${MIAB_SERVICES[@]}"; do
        echo -e "Starting $service..."
        if ! systemctl start "$service" 2>/dev/null; then
            echo -e "${YELLOW}Warning: Failed to start $service${NC}"
            failed_services="$failed_services $service"
        fi
    done
    
    if [ -z "$failed_services" ]; then
        echo -e "${GREEN}All Mail-in-a-Box services started successfully.${NC}"
        SERVICES_STOPPED=false
        return 0
    else
        echo -e "${YELLOW}Warning: Failed to start some services:${NC}$failed_services"
        echo -e "${YELLOW}Some manual intervention may be required.${NC}"
        SERVICES_STOPPED=false
        return 1
    fi
}

# Function to handle errors and cleanup
function handle_error {
    local error_message=$1
    echo -e "\n${RED}ERROR: $error_message${NC}"
    
    # Restart services if they were stopped
    if [ "$STOP_SERVICES" = true ] && [ "$SERVICES_STOPPED" = true ]; then
        echo -e "\n${YELLOW}Attempting to restart Mail-in-a-Box services due to error...${NC}"
        start_miab_services || echo -e "${RED}Failed to restart some services. Manual intervention may be required.${NC}"
    fi
    
    # Clean up temporary files
    cleanup
    
    exit 1
}

# Function to clean up temporary files
function cleanup {
    echo -e "\n${YELLOW}Cleaning up temporary files...${NC}"
    rm -f "${SSH_KEY_PATH}" "${SSH_KEY_PATH}.pub"
    echo -e "${GREEN}Temporary SSH keys removed.${NC}"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --username)
            USERNAME="$2"
            shift 2
            ;;
        --target-host)
            TARGET_HOST="$2"
            shift 2
            ;;
        --source-path)
            SOURCE_PATH="$2"
            shift 2
            ;;
        --target-path)
            TARGET_PATH="$2"
            shift 2
            ;;
        --config-path)
            CONFIG_PATH="$2"
            shift 2
            ;;
        --exclude)
            EXCLUDE="$2"
            shift 2
            ;;
        --new-ip)
            NEW_IP="$2"
            shift 2
            ;;
        --ssh-port)
            SSH_PORT="$2"
            shift 2
            ;;
        --stop-services)
            STOP_SERVICES=true
            shift
            ;;
        --ignore-partial)
            IGNORE_PARTIAL=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help)
            show_usage
            ;;
        *)
            echo -e "${RED}Error: Unknown option $1${NC}"
            show_usage
            ;;
    esac
done

# Check required parameters
if [ -z "$USERNAME" ] || [ -z "$TARGET_HOST" ] || [ -z "$NEW_IP" ]; then
    echo -e "${RED}Error: Missing required parameters.${NC}"
    show_usage
fi

# Validate IP address
if ! validate_ip "$NEW_IP"; then
    echo -e "${RED}Error: Invalid IP address format: $NEW_IP${NC}"
    exit 1
fi

# Check dependencies
check_dependencies

# Display migration information
echo -e "\n${BOLD}Mail-in-a-Box Migration${NC}"
echo -e "Source path: $SOURCE_PATH"
echo -e "Target server: $USERNAME@$TARGET_HOST:$TARGET_PATH"
echo -e "Config file: $CONFIG_PATH"
echo -e "New IP address: $NEW_IP"
if [ -n "$EXCLUDE" ]; then
    echo -e "Excluding: $EXCLUDE"
fi
if [ "$STOP_SERVICES" = true ]; then
    echo -e "Services: ${YELLOW}Will be stopped during transfer${NC}"
else
    echo -e "Services: ${GREEN}Will remain running during transfer${NC}"
fi
if [ "$IGNORE_PARTIAL" = true ]; then
    echo -e "Partial transfers: ${YELLOW}Will be ignored${NC}"
fi
if [ "$DRY_RUN" = true ]; then
    echo -e "Mode: ${YELLOW}DRY RUN${NC}"
fi

# Generate SSH key pair
if ! generate_ssh_key; then
    handle_error "Failed to generate SSH key pair"
fi

# Wait for user to add the SSH key to the target server
echo -e "\n${BOLD}Please add the above public key to the authorized_keys file on the target server.${NC}"
echo -e "You can use the following command on the target server:"
echo -e "${YELLOW}echo '$(cat "${SSH_KEY_PATH}.pub")' >> ~/.ssh/authorized_keys${NC}"
read -p "Press Enter once you have added the key to continue... " -r

# Test SSH connection
while ! test_ssh_connection; do
    read -p "Would you like to try again? (y/n): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${RED}Migration aborted.${NC}"
        cleanup
        exit 1
    fi
done

# Stop Mail-in-a-Box services on source server if requested
if [ "$STOP_SERVICES" = true ]; then
    if [ "$DRY_RUN" = false ]; then
        echo -e "\n${BOLD}The script will now stop all Mail-in-a-Box services on the source server.${NC}"
        read -p "Press Enter to continue or Ctrl+C to abort... " -r
        if ! stop_miab_services; then
            handle_error "Failed to stop Mail-in-a-Box services"
        fi
    else
        echo -e "\n${YELLOW}DRY RUN: Would stop all Mail-in-a-Box services on the source server.${NC}"
    fi
else
    echo -e "\n${YELLOW}Note: Mail-in-a-Box services will remain running during transfer.${NC}"
    echo -e "${YELLOW}If you experience issues, consider using the --stop-services option.${NC}"
fi

# Sync files
if ! sync_files; then
    if [ "$IGNORE_PARTIAL" = true ]; then
        echo -e "${YELLOW}Continuing despite file sync issues (--ignore-partial flag is set)${NC}"
    else
        handle_error "Failed to sync files"
    fi
fi

# Update mailinabox.conf
if ! update_mailinabox_conf; then
    handle_error "Failed to update mailinabox.conf"
fi

# Start Mail-in-a-Box services on source server if they were stopped
if [ "$STOP_SERVICES" = true ] && [ "$SERVICES_STOPPED" = true ]; then
    if [ "$DRY_RUN" = false ]; then
        echo -e "\n${BOLD}The script will now restart all Mail-in-a-Box services on the source server.${NC}"
        read -p "Press Enter to continue or Ctrl+C to abort... " -r
        if ! start_miab_services; then
            echo -e "${YELLOW}Warning: Some services failed to start. Manual intervention may be required.${NC}"
            # Continue execution despite service start failures
        fi
    else
        echo -e "\n${YELLOW}DRY RUN: Would restart all Mail-in-a-Box services on the source server.${NC}"
    fi
fi

# Final message
if [ "$DRY_RUN" = false ]; then
    echo -e "\n${GREEN}${BOLD}Mail-in-a-Box migration completed successfully!${NC}"
    echo -e "\n${YELLOW}IMPORTANT: ${RED}You MUST reinstall Mail-in-a-Box on the target server${YELLOW} to ensure proper configuration.${NC}"
    echo -e "The data has been transferred, but Mail-in-a-Box needs to be reinstalled to update all configurations."
    echo -e "\n${YELLOW}Next steps:${NC}"
    echo -e "1. SSH into the target server: ssh $USERNAME@$TARGET_HOST"
    echo -e "2. Reinstall Mail-in-a-Box on the target server: curl -s https://mailinabox.email/setup.sh | sudo bash"
    echo -e "3. Update DNS records to point to the new server IP: $NEW_IP"
    echo -e "4. Test mail functionality on the new server"
    echo -e "\n${YELLOW}Note:${NC} During reinstallation, Mail-in-a-Box will detect existing data and preserve it."
else
    echo -e "\n${YELLOW}${BOLD}Mail-in-a-Box dry run completed. No changes were made.${NC}"
    echo -e "Run the command without --dry-run to perform the actual migration."
fi

# Clean up
cleanup

exit 0
