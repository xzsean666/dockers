#!/bin/bash

# WAL-G PostgreSQL Backup Setup Script
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if required tools are installed
check_requirements() {
    log "Checking requirements..."
    
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        error "Docker Compose is not installed. Please install Docker Compose first."
        exit 1
    fi
    
    log "All requirements satisfied."
}

# Function to setup environment file
setup_env() {
    if [ ! -f .env ]; then
        if [ -f .example.env ]; then
            log "Creating .env from .example.env..."
            cp .example.env .env
            warn "Please edit .env file to configure your S3 settings:"
            warn "  - WALG_S3_PREFIX"
            warn "  - AWS_ACCESS_KEY_ID"
            warn "  - AWS_SECRET_ACCESS_KEY"
            warn "  - AWS_REGION"
        else
            error ".example.env not found. Cannot create .env file."
            exit 1
        fi
    else
        log ".env file already exists."
    fi
}

# Function to validate S3 configuration
validate_s3_config() {
    log "Validating S3 configuration..."
    
    source .env
    
    if [ "$WALG_S3_PREFIX" == "s3://your-backup-bucket/postgresql-backups" ]; then
        error "Please update WALG_S3_PREFIX in .env file with your actual S3 bucket path."
        exit 1
    fi
    
    if [ "$AWS_ACCESS_KEY_ID" == "your-r2-api-token" ] || [ "$AWS_ACCESS_KEY_ID" == "your-access-key-id" ]; then
        error "Please update AWS_ACCESS_KEY_ID in .env file with your actual S3/R2 access key."
        exit 1
    fi
    
    if [ "$AWS_SECRET_ACCESS_KEY" == "your-r2-secret-key" ] || [ "$AWS_SECRET_ACCESS_KEY" == "your-secret-access-key" ]; then
        error "Please update AWS_SECRET_ACCESS_KEY in .env file with your actual S3/R2 secret key."
        exit 1
    fi
    
    log "S3 configuration looks good."
}

# Function to build Docker image
build_image() {
    log "Building WAL-G Docker image..."
    docker-compose build --no-cache
    
    if [ $? -eq 0 ]; then
        log "Docker image built successfully."
    else
        error "Failed to build Docker image."
        exit 1
    fi
}

# Function to start services
start_services() {
    log "Starting PostgreSQL and WAL-G services..."
    docker-compose up -d
    
    if [ $? -eq 0 ]; then
        log "Services started successfully."
    else
        error "Failed to start services."
        exit 1
    fi
}

# Function to wait for PostgreSQL to be ready
wait_for_postgres() {
    log "Waiting for PostgreSQL to be ready..."
    
    source .env
    
    for i in {1..30}; do
        if docker-compose exec -T postgresql-master pg_isready -h localhost -p 5432 -U ${POSTGRESQL_USERNAME} &> /dev/null; then
            log "PostgreSQL is ready."
            return 0
        fi
        
        echo -n "."
        sleep 2
    done
    
    error "PostgreSQL failed to start within 60 seconds."
    return 1
}

# Function to test WAL-G setup
test_walg_setup() {
    log "Testing WAL-G setup..."
    
    # Wait a bit for WAL-G to initialize
    sleep 10
    
    # Test WAL-G connection
    docker-compose exec -T wal-g-backup wal-g backup-list || {
        warn "WAL-G backup-list failed. This is normal for first run."
    }
    
    log "WAL-G setup test completed."
}

# Function to show status
show_status() {
    log "Current status:"
    docker-compose ps
    
    echo ""
    log "To view logs:"
    echo "  docker-compose logs -f postgresql-master"
    echo "  docker-compose logs -f wal-g-backup"
    
    echo ""
    log "To perform manual backup:"
    echo "  docker-compose exec wal-g-backup /backup/scripts/manual-backup.sh"
    
    echo ""
    log "To list backups:"
    echo "  docker-compose exec wal-g-backup wal-g backup-list"
}

# Main execution
main() {
    log "Starting WAL-G PostgreSQL Backup Setup..."
    
    check_requirements
    setup_env
    
    # Ask user if they want to validate config
    read -p "Do you want to validate S3 configuration? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        validate_s3_config
    else
        warn "Skipping S3 configuration validation. Make sure to configure .env properly."
        warn "You can run './test-r2.sh' later to test your S3/R2 connection."
    fi
    
    build_image
    start_services
    wait_for_postgres
    test_walg_setup
    show_status
    
    log "Setup completed successfully!"
    log "Check the README.md for detailed usage instructions."
}

# Run main function
main "$@"
