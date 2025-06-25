#!/bin/bash

# Arbitrage Bot Monitoring Configuration Script
# Sets up comprehensive monitoring for the Solana arbitrage bot

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
GRAFANA_PORT=3000
PROMETHEUS_PORT=9090
ALERT_MANAGER_PORT=9093
BOT_METRICS_PORT=8080

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

install_monitoring_stack() {
    log_info "Installing monitoring stack..."
    
    # Create monitoring directory
    mkdir -p /opt/monitoring
    cd /opt/monitoring
    
    # Create docker-compose for monitoring stack
    cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
      - '--storage.tsdb.retention.time=200h'
      - '--web.enable-lifecycle'
    restart: unless-stopped

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    ports:
      - "3000:3000"
    volumes:
      - grafana_data:/var/lib/grafana
      - ./grafana/provisioning:/etc/grafana/provisioning
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin123
      - GF_USERS_ALLOW_SIGN_UP=false
    restart: unless-stopped

  alertmanager:
    image: prom/alertmanager:latest
    container_name: alertmanager
    ports:
      - "9093:9093"
    volumes:
      - ./alertmanager.yml:/etc/alertmanager/alertmanager.yml
    restart: unless-stopped

  node-exporter:
    image: prom/node-exporter:latest
    container_name: node-exporter
    ports:
      - "9100:9100"
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.rootfs=/rootfs'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'
    restart: unless-stopped

volumes:
  prometheus_data:
  grafana_data:
EOF

    log_success "Docker compose configuration created"
}

create_prometheus_config() {
    log_info "Creating Prometheus configuration..."
    
    cat > prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - "alert_rules.yml"

alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - alertmanager:9093

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']

  - job_name: 'arbitrage-bot'
    static_configs:
      - targets: ['host.docker.internal:8080']
    metrics_path: '/metrics'
    scrape_interval: 5s

  - job_name: 'docker'
    static_configs:
      - targets: ['host.docker.internal:9323']
EOF

    # Create alert rules
    cat > alert_rules.yml << 'EOF'
groups:
  - name: arbitrage_bot_alerts
    rules:
      - alert: BotDown
        expr: up{job="arbitrage-bot"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Arbitrage bot is down"
          description: "The arbitrage bot has been down for more than 1 minute"

      - alert: HighCPUUsage
        expr: 100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage detected"
          description: "CPU usage is above 80% for more than 5 minutes"

      - alert: HighMemoryUsage
        expr: (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100 > 90
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage detected"
          description: "Memory usage is above 90% for more than 5 minutes"

      - alert: LowProfitability
        expr: arbitrage_bot_profit_rate < 0.01
        for: 30m
        labels:
          severity: warning
        annotations:
          summary: "Low profitability detected"
          description: "Bot profitability is below 1% for more than 30 minutes"

      - alert: NoOpportunities
        expr: arbitrage_bot_opportunities_found == 0
        for: 15m
        labels:
          severity: warning
        annotations:
          summary: "No arbitrage opportunities found"
          description: "No profitable opportunities found for more than 15 minutes"
EOF

    log_success "Prometheus configuration created"
}

create_alertmanager_config() {
    log_info "Creating Alertmanager configuration..."
    
    cat > alertmanager.yml << 'EOF'
global:
  smtp_smarthost: 'localhost:587'
  smtp_from: 'alerts@arbitrage-bot.local'

route:
  group_by: ['alertname']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 1h
  receiver: 'web.hook'

receivers:
  - name: 'web.hook'
    webhook_configs:
      - url: 'http://host.docker.internal:5001/webhook'
        send_resolved: true

  - name: 'slack'
    slack_configs:
      - api_url: 'YOUR_SLACK_WEBHOOK_URL'
        channel: '#arbitrage-alerts'
        title: 'Arbitrage Bot Alert'
        text: '{{ range .Alerts }}{{ .Annotations.summary }}{{ end }}'

  - name: 'email'
    email_configs:
      - to: 'admin@yourdomain.com'
        subject: 'Arbitrage Bot Alert'
        body: |
          {{ range .Alerts }}
          Alert: {{ .Annotations.summary }}
          Description: {{ .Annotations.description }}
          {{ end }}
EOF

    log_success "Alertmanager configuration created"
}

create_grafana_dashboards() {
    log_info "Creating Grafana dashboards..."
    
    mkdir -p grafana/provisioning/dashboards
    mkdir -p grafana/provisioning/datasources
    
    # Datasource configuration
    cat > grafana/provisioning/datasources/prometheus.yml << 'EOF'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
EOF

    # Dashboard provisioning
    cat > grafana/provisioning/dashboards/dashboard.yml << 'EOF'
apiVersion: 1

providers:
  - name: 'default'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /etc/grafana/provisioning/dashboards
EOF

    # Arbitrage bot dashboard
    cat > grafana/provisioning/dashboards/arbitrage-bot.json << 'EOF'
{
  "dashboard": {
    "id": null,
    "title": "Arbitrage Bot Dashboard",
    "tags": ["arbitrage", "solana"],
    "timezone": "browser",
    "panels": [
      {
        "id": 1,
        "title": "Total Profit (USD)",
        "type": "stat",
        "targets": [
          {
            "expr": "arbitrage_bot_total_profit_usd",
            "refId": "A"
          }
        ],
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0}
      },
      {
        "id": 2,
        "title": "Opportunities Found",
        "type": "graph",
        "targets": [
          {
            "expr": "rate(arbitrage_bot_opportunities_found[5m])",
            "refId": "A"
          }
        ],
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0}
      },
      {
        "id": 3,
        "title": "Success Rate",
        "type": "stat",
        "targets": [
          {
            "expr": "arbitrage_bot_success_rate",
            "refId": "A"
          }
        ],
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8}
      },
      {
        "id": 4,
        "title": "System Resources",
        "type": "graph",
        "targets": [
          {
            "expr": "100 - (avg(irate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)",
            "refId": "A",
            "legendFormat": "CPU Usage %"
          },
          {
            "expr": "(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100",
            "refId": "B",
            "legendFormat": "Memory Usage %"
          }
        ],
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 8}
      }
    ],
    "time": {
      "from": "now-1h",
      "to": "now"
    },
    "refresh": "5s"
  }
}
EOF

    log_success "Grafana dashboards created"
}

create_webhook_server() {
    log_info "Creating webhook server for alerts..."
    
    cat > webhook_server.py << 'EOF'
#!/usr/bin/env python3
"""
Simple webhook server for processing Alertmanager alerts
"""

from flask import Flask, request, jsonify
import json
import requests
import os
from datetime import datetime

app = Flask(__name__)

SLACK_WEBHOOK = os.getenv('SLACK_WEBHOOK_URL')
DISCORD_WEBHOOK = os.getenv('DISCORD_WEBHOOK_URL')

@app.route('/webhook', methods=['POST'])
def webhook():
    data = request.json
    
    for alert in data.get('alerts', []):
        status = alert.get('status')
        summary = alert.get('annotations', {}).get('summary', 'Unknown alert')
        description = alert.get('annotations', {}).get('description', '')
        
        message = f"🚨 **{status.upper()}**: {summary}\n{description}"
        
        # Send to Slack
        if SLACK_WEBHOOK:
            send_slack_alert(message)
        
        # Send to Discord
        if DISCORD_WEBHOOK:
            send_discord_alert(message)
    
    return jsonify({'status': 'ok'})

def send_slack_alert(message):
    try:
        payload = {
            'text': message,
            'username': 'Arbitrage Bot',
            'icon_emoji': ':robot_face:'
        }
        requests.post(SLACK_WEBHOOK, json=payload)
    except Exception as e:
        print(f"Failed to send Slack alert: {e}")

def send_discord_alert(message):
    try:
        payload = {
            'content': message,
            'username': 'Arbitrage Bot'
        }
        requests.post(DISCORD_WEBHOOK, json=payload)
    except Exception as e:
        print(f"Failed to send Discord alert: {e}")

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5001)
EOF

    chmod +x webhook_server.py
    log_success "Webhook server created"
}

start_monitoring() {
    log_info "Starting monitoring stack..."
    
    # Start monitoring services
    docker-compose up -d
    
    # Wait for services to start
    sleep 30
    
    # Check if services are running
    if docker-compose ps | grep -q "Up"; then
        log_success "Monitoring stack started successfully"
        
        echo ""
        echo "=================================="
        echo "   MONITORING STACK READY"
        echo "=================================="
        echo ""
        echo "Access URLs:"
        echo "  Grafana:      http://$(hostname -I | awk '{print $1}'):3000"
        echo "  Prometheus:   http://$(hostname -I | awk '{print $1}'):9090"
        echo "  Alertmanager: http://$(hostname -I | awk '{print $1}'):9093"
        echo ""
        echo "Default Credentials:"
        echo "  Grafana: admin / admin123"
        echo ""
        echo "Next Steps:"
        echo "  1. Configure Slack/Discord webhooks in alertmanager.yml"
        echo "  2. Import custom dashboards in Grafana"
        echo "  3. Set up SSL certificates for production"
        echo ""
    else
        log_error "Failed to start monitoring stack"
        docker-compose logs
        exit 1
    fi
}

# Main execution
main() {
    log_info "Setting up monitoring for Arbitrage Bot..."
    
    check_root
    install_monitoring_stack
    create_prometheus_config
    create_alertmanager_config
    create_grafana_dashboards
    create_webhook_server
    start_monitoring
    
    log_success "Monitoring setup completed!"
}

# Handle command line arguments
case "${1:-setup}" in
    "setup")
        main
        ;;
    "start")
        cd /opt/monitoring
        docker-compose up -d
        log_success "Monitoring stack started"
        ;;
    "stop")
        cd /opt/monitoring
        docker-compose down
        log_success "Monitoring stack stopped"
        ;;
    "restart")
        cd /opt/monitoring
        docker-compose restart
        log_success "Monitoring stack restarted"
        ;;
    "logs")
        cd /opt/monitoring
        docker-compose logs -f
        ;;
    "status")
        cd /opt/monitoring
        docker-compose ps
        ;;
    *)
        echo "Usage: $0 {setup|start|stop|restart|logs|status}"
        echo ""
        echo "Commands:"
        echo "  setup   - Full monitoring setup (default)"
        echo "  start   - Start monitoring services"
        echo "  stop    - Stop monitoring services"
        echo "  restart - Restart monitoring services"
        echo "  logs    - View monitoring logs"
        echo "  status  - Show service status"
        exit 1
        ;;
esac

