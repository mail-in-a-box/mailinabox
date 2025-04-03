# Mail-in-a-Box Migration Script

**Author:** Ahmad Kouider  
**Created:** April 3, 2025

## Overview

The `migrate-miab.sh` script provides a comprehensive solution for migrating Mail-in-a-Box installations from one server to another. It handles the secure transfer of data, configuration updates, and service management to ensure a smooth migration process.

## Features

- **Secure Data Transfer**: Uses rsync over SSH for efficient and secure file transfer
- **Configuration Management**: Automatically updates the Mail-in-a-Box configuration with the new IP address
- **Service Control**: Optional stopping and starting of Mail-in-a-Box services during migration
- **Error Handling**: Robust error detection and recovery with automatic service restoration
- **Partial Transfer Support**: Special handling for partial transfers (common with large installations)
- **Dry Run Mode**: Test the migration process without making any changes

## Prerequisites

- SSH access to both source and target servers
- rsync installed on the source server
- Sufficient disk space on the target server
- Mail-in-a-Box installed on the source server

## Usage

### Basic Usage

```bash
./migrate-miab.sh --username admin --target-host 192.168.1.100 --new-ip 203.0.113.10
```

### All Available Options

| Option | Description | Default |
|--------|-------------|---------|
| `--username USERNAME` | SSH username for target server | (required) |
| `--target-host HOST` | IP address or domain of target server | (required) |
| `--new-ip IP` | Public IP address of the new target machine | (required) |
| `--source-path PATH` | Path to Mail-in-a-Box files | /home/user-data |
| `--target-path PATH` | Destination path on target server | /home/user-data |
| `--config-path PATH` | Path to mailinabox.conf file | /etc/mailinabox.conf |
| `--exclude LIST` | Comma-separated list of files/folders to exclude | (none) |
| `--ssh-port PORT` | SSH port to use | 22 |
| `--stop-services` | Stop Mail-in-a-Box services during transfer | (default: keep running) |
| `--ignore-partial` | Continue migration even if some files fail to transfer | (default: prompt user) |
| `--dry-run` | Simulate the transfer without making changes | (default: false) |
| `--help` | Display help message | |

### Example Commands

**Standard Migration:**
```bash
./migrate-miab.sh --username admin --target-host mail2.example.com --new-ip 203.0.113.10
```

**Migration with Service Stopping:**
```bash
./migrate-miab.sh --username admin --target-host mail2.example.com --new-ip 203.0.113.10 --stop-services
```

**Excluding Certain Directories:**
```bash
./migrate-miab.sh --username admin --target-host mail2.example.com --new-ip 203.0.113.10 --exclude 'backup,logs,tmp'
```

**Dry Run Test:**
```bash
./migrate-miab.sh --username admin --target-host mail2.example.com --new-ip 203.0.113.10 --dry-run
```

## Migration Process

1. **Preparation**:
   - Validates all input parameters
   - Generates a temporary SSH key pair
   - Prompts you to add the key to the target server

2. **Service Management** (if `--stop-services` is used):
   - Stops all Mail-in-a-Box services on the source server
   - This helps prevent file corruption during transfer

3. **Data Transfer**:
   - Uses rsync to efficiently transfer all Mail-in-a-Box data
   - Handles partial transfers with interactive prompting

4. **Configuration Update**:
   - Updates the mailinabox.conf file with the new IP address
   - Transfers the updated configuration to the target server

5. **Service Restoration**:
   - Restarts any services that were stopped (if applicable)
   - Ensures the source server returns to its original state

## Important Notes

### Partial Transfers

When transferring large Mail-in-a-Box installations, you may encounter "partial transfer" errors (rsync code 23). This typically happens because:

- Some files are actively being used (open files)
- Permission issues prevent access to certain files
- Special system files cannot be transferred normally

The script provides two ways to handle this:
1. **Interactive prompt**: Choose whether to continue or abort
2. **Automatic continuation**: Use the `--ignore-partial` flag

### Post-Migration Steps

After the migration completes successfully, you **MUST**:

1. **Reinstall Mail-in-a-Box** on the target server:
   ```bash
   curl -s https://mailinabox.email/setup.sh | sudo bash
   ```
   This ensures all configurations are properly updated while preserving your transferred data.

2. **Update DNS records** to point to the new server IP address

3. **Test mail functionality** on the new server

## Troubleshooting

### Common Issues

1. **SSH Connection Failures**:
   - Ensure the public key was added to ~/.ssh/authorized_keys on the target server
   - Verify the SSH port is correct (default: 22)
   - Check for firewall rules blocking SSH connections

2. **File Transfer Errors**:
   - Consider using the `--stop-services` option to prevent open file issues
   - Use `--exclude` to skip problematic directories
   - For partial transfers, use `--ignore-partial` if you're confident in the data integrity

3. **Configuration File Not Found**:
   - If your Mail-in-a-Box has a non-standard configuration path, use the `--config-path` option

## Security Considerations

- The script generates a temporary SSH key pair for the migration
- Keys are automatically deleted after the migration completes
- No passwords are stored or transmitted
- All data is transferred over encrypted SSH connections

## License

This script is provided as-is with no warranty. Use at your own risk.
