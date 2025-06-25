#!/bin/bash

# Solana Arbitrage Bot - VPS Deployment Script
# This script automates the deployment of the arbitrage bot to a Vultr VPS

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
REPO_URL="https://github.com/Limitlessjacko/solana-arbitrage-bot.git"
APP_DIR="/opt/solana-arbitrage-bot"
SERVICE_NAME="arbitrage-bot"
LOG_DIR="/var/log/arbitrage-bot"

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

install_dependencies() {
    log_info "Installing system dependencies..."
    
    # Update system
    apt update && apt upgrade -y
    
    # Install required packages
    apt install -y \
        docker.io \
        docker-compose \
        git \
        curl \
        wget \
        htop \
        ufw \
        fail2ban \
        logrotate
    
    # Enable and start Docker
    systemctl enable docker
    systemctl start docker
    
    # Add current user to docker group (if not root)
    if [[ $SUDO_USER ]]; then
        usermod -aG docker $SUDO_USER
    fi
    
    log_success "Dependencies installed successfully"
}

setup_firewall() {
    log_info "Configuring firewall..."
    
    # Reset UFW to defaults
    ufw --force reset
    
    # Default policies
    ufw default deny incoming
    ufw default allow outgoing
    
    # Allow SSH (adjust port if needed)
    ufw allow 22/tcp
    
    # Allow HTTP/HTTPS for monitoring (optional)
    ufw allow 80/tcp
    ufw allow 443/tcp
    
    # Enable firewall
    ufw --force enable
    
    log_success "Firewall configured"
}

clone_repository() {
    log_info "Cloning repository..."
    
    # Remove existing directory if it exists
    if [[ -d "$APP_DIR" ]]; then
        log_warning "Removing existing application directory"
        rm -rf "$APP_DIR"
    fi
    
    # Clone repository
    git clone "$REPO_URL" "$APP_DIR"
    cd "$APP_DIR"
    
    log_success "Repository cloned to $APP_DIR"
}

setup_environment() {
    log_info "Setting up environment..."
    
    cd "$APP_DIR"
    
    # Copy environment template
    if [[ ! -f ".env" ]]; then
        cp .env.example .env
        log_warning "Please edit .env file with your configuration:"
        log_warning "nano $APP_DIR/.env"
        log_warning "Press Enter when done..."
        read -r
    fi
    
    # Create log directory
    mkdir -p "$LOG_DIR"
    chown -R 1000:1000 "$LOG_DIR"  # Match container user
    
    log_success "Environment configured"
}

build_container() {
    log_info "Building Docker container..."
    
    cd "$APP_DIR"
    
    # Build the container
    docker build -t arb-bot:latest .
    
    log_success "Container built successfully"
}

create_systemd_service() {
    log_info "Creating systemd service..."
    
    cat > "/etc/systemd/system/${SERVICE_NAME}.service" << EOF
[Unit]
Description=Solana Arbitrage Bot
Requires=docker.service
After=docker.service

[Service]
Type=simple
User=root
WorkingDirectory=$APP_DIR
ExecStartPre=-/usr/bin/docker stop arb-bot
ExecStartPre=-/usr/bin/docker rm arb-bot
ExecStart=/usr/bin/docker run --name arb-bot --rm --env-file .env -v $LOG_DIR:/app/logs arb-bot:latest
ExecStop=/usr/bin/docker stop arb-bot
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd and enable service
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    
    log_success "Systemd service created"
}

setup_monitoring() {
    log_info "Setting up monitoring..."
    
    # Create monitoring script
    cat > "/usr/local/bin/arb-bot-monitor" << 'EOF'
#!/bin/bash

# Simple monitoring script for arbitrage bot
SERVICE_NAME="arbitrage-bot"
LOG_FILE="/var/log/arbitrage-bot/monitor.log"

check_service() {
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo "$(date): Service is running" >> "$LOG_FILE"
        return 0
    else
        echo "$(date): Service is down, attempting restart" >> "$LOG_FILE"
        systemctl restart "$SERVICE_NAME"
        return 1
    fi
}

check_docker() {
    if docker ps | grep -q "arb-bot"; then
        echo "$(date): Container is running" >> "$LOG_FILE"
        return 0
    else
        echo "$(date): Container not found" >> "$LOG_FILE"
        return 1
    fi
}

# Run checks
check_service
check_docker

# Log system resources
echo "$(date): Memory: $(free -h | grep Mem | awk '{print $3"/"$2}')" >> "$LOG_FILE"
echo "$(date): Disk: $(df -h / | tail -1 | awk '{print $3"/"$2" ("$5" used)"}')" >> "$LOG_FILE"
EOF

    chmod +x "/usr/local/bin/arb-bot-monitor"
    
    # Add cron job for monitoring
    echo "*/5 * * * * /usr/local/bin/arb-bot-monitor" | crontab -
    
    log_success "Monitoring configured"
}

setup_log_rotation() {
    log_info "Setting up log rotation..."
    
    cat > "/etc/logrotate.d/arbitrage-bot" << EOF
$LOG_DIR/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
    postrotate
        systemctl reload $SERVICE_NAME || true
    endscript
}
EOF

    log_success "Log rotation configured"
}

start_service() {
    log_info "Starting arbitrage bot service..."
    
    systemctl start "$SERVICE_NAME"
    
    # Wait a moment and check status
    sleep 5
    
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        log_success "Service started successfully"
        log_info "Checking logs..."
        journalctl -u "$SERVICE_NAME" --no-pager -n 20
    else
        log_error "Service failed to start"
        log_error "Check logs with: journalctl -u $SERVICE_NAME"
        exit 1
    fi
}

show_status() {
    echo ""
    echo "=================================="
    echo "   DEPLOYMENT COMPLETE"
    echo "=================================="
    echo ""
    echo "Service Status:"
    systemctl status "$SERVICE_NAME" --no-pager -l
    echo ""
    echo "Useful Commands:"
    echo "  View logs:     journalctl -u $SERVICE_NAME -f"
    echo "  Restart:       systemctl restart $SERVICE_NAME"
    echo "  Stop:          systemctl stop $SERVICE_NAME"
    echo "  Status:        systemctl status $SERVICE_NAME"
    echo "  Monitor:       docker logs -f arb-bot"
    echo ""
    echo "Files:"
    echo "  App directory: $APP_DIR"
    echo "  Logs:          $LOG_DIR"
    echo "  Config:        $APP_DIR/.env"
    echo ""
}

# Main deployment flow
main() {
    log_info "Starting Solana Arbitrage Bot deployment..."
    
    check_root
    install_dependencies
    setup_firewall
    clone_repository
    setup_environment
    build_container
    create_systemd_service
    setup_monitoring
    setup_log_rotation
    start_service
    show_status
    
    log_success "Deployment completed successfully!"
}

# Handle command line arguments
case "${1:-deploy}" in
    "deploy")
        main
        ;;
    "update")
        log_info "Updating application..."
        cd "$APP_DIR"
        git pull
        docker build -t arb-bot:latest .
        systemctl restart "$SERVICE_NAME"
        log_success "Update completed"
        ;;
    "logs")
        journalctl -u "$SERVICE_NAME" -f
        ;;
    "status")
        systemctl status "$SERVICE_NAME"
        ;;
    "stop")
        systemctl stop "$SERVICE_NAME"
        log_success "Service stopped"
        ;;
    "start")
        systemctl start "$SERVICE_NAME"
        log_success "Service started"
        ;;
    *)
        echo "Usage: $0 {deploy|update|logs|status|stop|start}"
        echo ""
        echo "Commands:"
        echo "  deploy  - Full deployment (default)"
        echo "  update  - Update and restart"
        echo "  logs    - View live logs"
        echo "  status  - Show service status"
        echo "  stop    - Stop the service"
        echo "  start   - Start the service"
        exit 1
        ;;
esac

