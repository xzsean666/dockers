#!/bin/bash

# pgBackRest Helper Script
# This script helps manage pgBackRest operations in Docker containers

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to load environment variables
load_env() {
    local env_file="$1"
    if [[ -f "$env_file" ]]; then
        print_info "Loading environment from $env_file"
        set -o allexport
        source "$env_file"
        set +o allexport
    else
        print_error "Environment file $env_file not found!"
        exit 1
    fi
}

# Function to check if container is running
check_container() {
    local container_name="$1"
    if ! docker ps --filter "name=$container_name" --format "table {{.Names}}" | grep -q "$container_name"; then
        print_error "Container $container_name is not running!"
        exit 1
    fi
    print_info "Container $container_name is running"
}

# Function to execute pgbackrest command in container
exec_pgbackrest() {
    local container_name="$1"
    shift
    local cmd="$@"
    
    print_info "Executing pgbackrest command in container $container_name: $cmd"
    
    # Set PostgreSQL password environment variable if available
    local pg_password="${POSTGRESQL_PASSWORD:-}"
    
    # Run pgbackrest as postgres user with proper environment
    if [[ -n "$pg_password" ]]; then
        docker exec -it "$container_name" bash -c "
            export PGPASSWORD='$pg_password'
            export PATH=\$PATH:/opt/bitnami/postgresql/bin
            su postgres -c 'pgbackrest $cmd'
        "
    else
        docker exec -it "$container_name" bash -c "
            export PATH=\$PATH:/opt/bitnami/postgresql/bin
            su postgres -c 'pgbackrest $cmd'
        "
    fi
}

# Function to initialize pgbackrest and create stanza
Init() {
    local container_name="$1"
    local stanza_name="${2:-main}"
    local pg_path="${3:-/bitnami/postgresql/data}"
    
    print_info "🚀 Starting pgBackRest initialization process..."
    
    # Step 1: Initialize pgbackrest environment
    print_info "📁 Creating pgbackrest directories..."
    docker exec "$container_name" bash -c "
        # Create all necessary pgbackrest directories
        mkdir -p /var/log/pgbackrest
        mkdir -p /etc/pgbackrest
        mkdir -p /tmp/pgbackrest
        mkdir -p /var/spool/pgbackrest
        mkdir -p /var/lib/pgbackrest
        mkdir -p /var/lib/pgbackrest/backup
        mkdir -p /var/lib/pgbackrest/archive
        
        # Set ownership to postgres user
        chown -R postgres:postgres /var/log/pgbackrest
        chown -R postgres:postgres /etc/pgbackrest
        chown -R postgres:postgres /tmp/pgbackrest
        chown -R postgres:postgres /var/spool/pgbackrest
        chown -R postgres:postgres /var/lib/pgbackrest
        
        # Set appropriate permissions
        chmod -R 750 /var/log/pgbackrest
        chmod -R 750 /etc/pgbackrest
        chmod -R 750 /tmp/pgbackrest
        chmod -R 750 /var/spool/pgbackrest
        chmod -R 750 /var/lib/pgbackrest
        
        echo 'Created pgbackrest directories:'
        ls -la /var/lib/ | grep pgbackrest
        ls -la /var/log/ | grep pgbackrest
    "
    
    # Step 1.5: Create pgbackrest configuration file
    print_info "📝 Creating pgbackrest configuration file..."
    local pg_password="${POSTGRESQL_PASSWORD:-}"
    
    docker exec "$container_name" bash -c "
        cat > /etc/pgbackrest/pgbackrest.conf << 'EOF'
[global]
repo1-path=/var/lib/pgbackrest
repo1-retention-full=2
log-level-console=info
log-level-file=debug

[${stanza_name}]
pg1-path=${pg_path}
pg1-port=5432
pg1-user=postgres
pg1-database=postgres
EOF
        chown postgres:postgres /etc/pgbackrest/pgbackrest.conf
        chmod 640 /etc/pgbackrest/pgbackrest.conf
        
        # Create .pgpass file for postgres user - find the correct home directory
        POSTGRES_HOME=\$(getent passwd postgres | cut -d: -f6)
        if [ -z \"\$POSTGRES_HOME\" ] || [ ! -d \"\$POSTGRES_HOME\" ]; then
            # For Bitnami, try common locations
            if [ -d \"/opt/bitnami/postgresql\" ]; then
                POSTGRES_HOME=\"/opt/bitnami/postgresql\"
            elif [ -d \"/home/postgres\" ]; then
                POSTGRES_HOME=\"/home/postgres\"
            else
                POSTGRES_HOME=\"/var/lib/postgresql\"
                mkdir -p \$POSTGRES_HOME
            fi
            chown postgres:postgres \$POSTGRES_HOME
        fi
        
        echo \"localhost:5432:*:postgres:${pg_password}\" > \$POSTGRES_HOME/.pgpass
        chown postgres:postgres \$POSTGRES_HOME/.pgpass
        chmod 600 \$POSTGRES_HOME/.pgpass
        echo \"Created .pgpass file at: \$POSTGRES_HOME/.pgpass\"
    "
    
    print_info "✅ pgbackrest environment initialized successfully"
    
    # Step 1.7: Verify PostgreSQL is running and accessible
    print_info "🔌 Verifying PostgreSQL connection..."
    local pg_password="${POSTGRESQL_PASSWORD:-}"
    
    docker exec "$container_name" bash -c "
        export PGPASSWORD='$pg_password'
        # Wait for PostgreSQL to be ready
        for i in {1..30}; do
            if pg_isready -h localhost -p 5432 -U postgres; then
                echo 'PostgreSQL is ready!'
                break
            else
                echo 'Waiting for PostgreSQL to be ready... (\$i/30)'
                sleep 2
            fi
        done
        
        # Test connection
        psql -h localhost -p 5432 -U postgres -d postgres -c 'SELECT version();' || {
            echo 'ERROR: Cannot connect to PostgreSQL!'
            exit 1
        }
    "
    
    # Step 2: Create stanza
    print_info "🔧 Creating stanza '$stanza_name' with pg1-path='$pg_path'"
    
    # Use postgres superuser for pgbackrest operations
    local pg_user="postgres"
    local pg_password="${POSTGRESQL_PASSWORD:-}"
    local pg_database="postgres"
    
    print_info "🔑 Using postgres superuser for pgbackrest operations"
    
    # Create stanza (configuration is now in pgbackrest.conf)
    print_info "📋 Debug info before stanza creation:"
    docker exec "$container_name" bash -c "
        echo '=== pgbackrest config ==='
        cat /etc/pgbackrest/pgbackrest.conf
        echo '=== directory permissions ==='
        ls -la /var/lib/pgbackrest/
        echo '=== postgres user info ==='
        id postgres
    "
    
    exec_pgbackrest "$container_name" \
        --stanza="$stanza_name" \
        stanza-create
        
    print_info "✅ Stanza created successfully!"
    
    # Step 3: Enable WAL archiving
    print_info "📝 Enabling PostgreSQL WAL archiving..."
    
    # Configure PostgreSQL for archiving
    docker exec "$container_name" bash -c "
        # Find postgresql.conf location
        PGCONF=\$(find /opt/bitnami/postgresql/conf -name 'postgresql.conf' 2>/dev/null | head -1)
        if [ -z \"\$PGCONF\" ]; then
            PGCONF=\$(find /bitnami/postgresql/conf -name 'postgresql.conf' 2>/dev/null | head -1)
        fi
        if [ -z \"\$PGCONF\" ]; then
            echo 'ERROR: Cannot find postgresql.conf'
            exit 1
        fi
        
        echo \"Found postgresql.conf at: \$PGCONF\"
        
        # Backup original config
        cp \"\$PGCONF\" \"\$PGCONF.backup-\$(date +%Y%m%d-%H%M%S)\"
        
        # Remove existing archive settings if any
        sed -i '/^archive_mode/d' \"\$PGCONF\"
        sed -i '/^archive_command/d' \"\$PGCONF\"
        sed -i '/^wal_level/d' \"\$PGCONF\"
        
        # Add new archive settings
        echo '' >> \"\$PGCONF\"
        echo '# pgBackRest WAL archiving settings' >> \"\$PGCONF\"
        echo 'wal_level = replica' >> \"\$PGCONF\"
        echo 'archive_mode = on' >> \"\$PGCONF\"
        echo 'archive_command = \\'pgbackrest --stanza=$stanza_name archive-push %p\\'' >> \"\$PGCONF\"
        echo 'max_wal_senders = 3' >> \"\$PGCONF\"
        echo 'wal_keep_size = 1GB' >> \"\$PGCONF\"
        
        echo 'Added pgBackRest archive settings to postgresql.conf'
        echo 'New settings:'
        tail -6 \"\$PGCONF\"
    "
    
    print_info "🔄 Restarting PostgreSQL to apply new configuration..."
    
    # Restart PostgreSQL to apply changes
    docker exec "$container_name" bash -c "
        # Use pg_ctl to restart PostgreSQL gracefully
        export PGDATA=/bitnami/postgresql/data
        su postgres -c 'pg_ctl restart -D /bitnami/postgresql/data -l /var/log/postgresql.log'
        
        # Wait for PostgreSQL to be ready
        echo 'Waiting for PostgreSQL to restart...'
        for i in {1..30}; do
            if pg_isready -h localhost -p 5432 -U postgres; then
                echo 'PostgreSQL restarted successfully!'
                break
            else
                echo 'Waiting for PostgreSQL... (\$i/30)'
                sleep 2
            fi
        done
    "
    
    # Verify archiving is enabled
    print_info "✅ Verifying WAL archiving configuration..."
    docker exec "$container_name" bash -c "
        export PGPASSWORD='${POSTGRESQL_PASSWORD:-}'
        psql -h localhost -p 5432 -U postgres -d postgres -c \"
            SELECT name, setting, context 
            FROM pg_settings 
            WHERE name IN ('archive_mode', 'archive_command', 'wal_level')
            ORDER BY name;
        \"
    "
        
    print_info "🎉 pgBackRest initialization completed successfully!"
    print_info "💡 Everything is configured! You can now run './pgbackrest-helper.sh check' and './pgbackrest-helper.sh backup full'"
}

# Function to enable PostgreSQL WAL archiving
enable_archive() {
    local container_name="$1"
    local stanza_name="${2:-main}"
    
    print_info "📝 Enabling PostgreSQL WAL archiving for stanza '$stanza_name'..."
    
    # Configure PostgreSQL for archiving
    docker exec "$container_name" bash -c "
        # Find postgresql.conf location
        PGCONF=\$(find /opt/bitnami/postgresql/conf -name 'postgresql.conf' 2>/dev/null | head -1)
        if [ -z \"\$PGCONF\" ]; then
            PGCONF=\$(find /bitnami/postgresql/conf -name 'postgresql.conf' 2>/dev/null | head -1)
        fi
        if [ -z \"\$PGCONF\" ]; then
            echo 'ERROR: Cannot find postgresql.conf'
            exit 1
        fi
        
        echo \"Found postgresql.conf at: \$PGCONF\"
        
        # Backup original config
        cp \"\$PGCONF\" \"\$PGCONF.backup-\$(date +%Y%m%d-%H%M%S)\"
        
        # Remove existing archive settings if any
        sed -i '/^archive_mode/d' \"\$PGCONF\"
        sed -i '/^archive_command/d' \"\$PGCONF\"
        sed -i '/^wal_level/d' \"\$PGCONF\"
        
        # Add new archive settings
        echo '' >> \"\$PGCONF\"
        echo '# pgBackRest WAL archiving settings' >> \"\$PGCONF\"
        echo 'wal_level = replica' >> \"\$PGCONF\"
        echo 'archive_mode = on' >> \"\$PGCONF\"
        echo 'archive_command = \\'pgbackrest --stanza=$stanza_name archive-push %p\\'' >> \"\$PGCONF\"
        echo 'max_wal_senders = 3' >> \"\$PGCONF\"
        echo 'wal_keep_size = 1GB' >> \"\$PGCONF\"
        
        echo 'Added pgBackRest archive settings to postgresql.conf'
        echo 'New settings:'
        tail -6 \"\$PGCONF\"
    "
    
    print_info "🔄 Restarting PostgreSQL to apply new configuration..."
    
    # Restart PostgreSQL to apply changes
    docker exec "$container_name" bash -c "
        # Use pg_ctl to restart PostgreSQL gracefully
        export PGDATA=/bitnami/postgresql/data
        su postgres -c 'pg_ctl restart -D /bitnami/postgresql/data -l /var/log/postgresql.log'
        
        # Wait for PostgreSQL to be ready
        echo 'Waiting for PostgreSQL to restart...'
        for i in {1..30}; do
            if pg_isready -h localhost -p 5432 -U postgres; then
                echo 'PostgreSQL restarted successfully!'
                break
            else
                echo 'Waiting for PostgreSQL... (\$i/30)'
                sleep 2
            fi
        done
    "
    
    # Verify archiving is enabled
    print_info "✅ Verifying WAL archiving configuration..."
    docker exec "$container_name" bash -c "
        export PGPASSWORD='${POSTGRESQL_PASSWORD:-}'
        psql -h localhost -p 5432 -U postgres -d postgres -c \"
            SELECT name, setting, context 
            FROM pg_settings 
            WHERE name IN ('archive_mode', 'archive_command', 'wal_level')
            ORDER BY name;
        \"
    "
    
    print_info "🎉 WAL archiving has been enabled successfully!"
    print_info "💡 You can now run './pgbackrest-helper.sh check' to verify the complete configuration"
}

# Function to check configuration
check_config() {
    local container_name="$1"
    local stanza_name="${2:-main}"
    local pg_path="${3:-/bitnami/postgresql/data}"
    
    print_info "Checking pgbackrest configuration for stanza '$stanza_name'"
    
    # Use postgres superuser for pgbackrest operations
    local pg_user="postgres"
    local pg_password="${POSTGRESQL_PASSWORD:-}"
    local pg_database="postgres"
    
    # Check configuration (configuration is now in pgbackrest.conf)
    exec_pgbackrest "$container_name" \
        --stanza="$stanza_name" \
        check
}

# Function to perform backup
backup() {
    local container_name="$1"
    local stanza_name="${2:-main}"
    local backup_type="${3:-incr}"
    
    print_info "Performing $backup_type backup for stanza '$stanza_name'"
    exec_pgbackrest "$container_name" --stanza="$stanza_name" --type="$backup_type" backup
}

# Function to show backup info
info() {
    local container_name="$1"
    local stanza_name="${2:-main}"
    
    print_info "Getting backup info for stanza '$stanza_name'"
    exec_pgbackrest "$container_name" --stanza="$stanza_name" info
}

# Function to show help
show_help() {
    cat << EOF
pgBackRest Helper Script

Usage: $0 [options] <command>

Options:
    -e, --env-file FILE     Specify environment file (default: signal/.env)
    -c, --container NAME    Override container name from env file
    -s, --stanza NAME       Stanza name (default: main)
    -p, --pg-path PATH      PostgreSQL data path (default: /bitnami/postgresql/data)
    -h, --help              Show this help

Commands:
    Init                    Complete initialization (directories + stanza + WAL archiving + restart)
    enable-archive          Enable PostgreSQL WAL archiving only (standalone use)
    check                   Check pgbackrest configuration
    backup [full|diff|incr] Perform backup (default: incr)
    info                    Show backup information
    shell                   Open shell in container
    exec <pgbackrest-cmd>   Execute custom pgbackrest command

Examples:
    $0 Init                 # Complete one-step initialization
    $0 check               # Check configuration
    $0 backup full         # Full backup
    $0 info                # Show backup info
    $0 enable-archive       # Enable archiving only (if needed separately)
    $0 exec --stanza=main --pg1-path=/bitnami/postgresql/data version

EOF
}

# Parse command line arguments
ENV_FILE=""
CONTAINER_NAME=""
STANZA_NAME="main"
PG_PATH="/bitnami/postgresql/data"

while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--env-file)
            ENV_FILE="$2"
            shift 2
            ;;
        -c|--container)
            CONTAINER_NAME="$2"
            shift 2
            ;;
        -s|--stanza)
            STANZA_NAME="$2"
            shift 2
            ;;
        -p|--pg-path)
            PG_PATH="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            break
            ;;
    esac
done

# Determine environment file
if [[ -z "$ENV_FILE" ]]; then
    if [[ -f "$SCRIPT_DIR/signal/.env" ]]; then
        ENV_FILE="$SCRIPT_DIR/signal/.env"
    elif [[ -f "$SCRIPT_DIR/.env" ]]; then
        ENV_FILE="$SCRIPT_DIR/.env"
    else
        print_error "No environment file found. Please specify with -e option or create signal/.env"
        exit 1
    fi
fi

# Load environment variables
load_env "$ENV_FILE"

# Use container name from env if not overridden
if [[ -z "$CONTAINER_NAME" ]]; then
    if [[ -z "${CONTAINER_NAME:-}" ]]; then
        print_error "CONTAINER_NAME not found in environment file and not specified with -c option"
        exit 1
    fi
fi

print_info "Using container: $CONTAINER_NAME"
print_info "Using stanza: $STANZA_NAME"
print_info "Using pg-path: $PG_PATH"

# Check if container is running
check_container "$CONTAINER_NAME"

# Execute command
COMMAND="${1:-help}"

case "$COMMAND" in
    Init)
        Init "$CONTAINER_NAME" "$STANZA_NAME" "$PG_PATH"
        ;;
    enable-archive)
        enable_archive "$CONTAINER_NAME" "$STANZA_NAME"
        ;;
    check)
        check_config "$CONTAINER_NAME" "$STANZA_NAME" "$PG_PATH"
        ;;
    backup)
        BACKUP_TYPE="${2:-incr}"
        backup "$CONTAINER_NAME" "$STANZA_NAME" "$BACKUP_TYPE"
        ;;
    info)
        info "$CONTAINER_NAME" "$STANZA_NAME"
        ;;
    shell)
        print_info "Opening shell in container $CONTAINER_NAME"
        docker exec -it "$CONTAINER_NAME" bash
        ;;
    exec)
        shift
        exec_pgbackrest "$CONTAINER_NAME" "$@"
        ;;
    help)
        show_help
        ;;
    *)
        print_error "Unknown command: $COMMAND"
        show_help
        exit 1
        ;;
esac
