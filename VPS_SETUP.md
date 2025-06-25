# VPS Deployment Instructions for Solana Arbitrage Bot

## Quick Deployment Guide

### 1. Create Vultr VPS Instance

**Recommended Specifications:**
- **OS**: Ubuntu 22.04 LTS
- **CPU**: 2+ cores (4 cores recommended)
- **RAM**: 4GB minimum (8GB recommended)
- **Storage**: 50GB SSD
- **Network**: 1Gbps connection

**Instance Creation:**
```bash
# Via Vultr Web Interface:
1. Login to Vultr dashboard
2. Click "Deploy New Server"
3. Choose "Cloud Compute"
4. Select location closest to major exchanges
5. Choose Ubuntu 22.04 x64
6. Select $20/month plan (4GB RAM, 2 CPU)
7. Add SSH key for secure access
8. Deploy instance
```

### 2. Initial VPS Setup

**Connect to VPS:**
```bash
ssh root@YOUR_VPS_IP
```

**Update System:**
```bash
apt update && apt upgrade -y
```

**Create Non-Root User (Optional but Recommended):**
```bash
adduser arbbot
usermod -aG sudo arbbot
su - arbbot
```

### 3. Automated Deployment

**Option A: One-Command Deployment**
```bash
curl -sSL https://raw.githubusercontent.com/Limitlessjacko/solana-arbitrage-bot/main/deploy.sh | sudo bash
```

**Option B: Manual Deployment**
```bash
# Clone repository
git clone https://github.com/Limitlessjacko/solana-arbitrage-bot.git
cd solana-arbitrage-bot

# Make deployment script executable
chmod +x deploy.sh

# Run deployment
sudo ./deploy.sh
```

### 4. Configuration

**Edit Environment Variables:**
```bash
sudo nano /opt/solana-arbitrage-bot/.env
```

**Required Configuration:**
```bash
# Solana Configuration
SOLANA_RPC_URL=https://api.mainnet-beta.solana.com
PRIVATE_KEY=your_base58_private_key_here
WALLET_PUBLIC_KEY=your_public_key_here

# Trading Parameters
MIN_PROFIT_THRESHOLD=10.0
MAX_SLIPPAGE=0.02
MAX_POSITION_SIZE=1000.0

# Monitoring (Optional)
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK
```

### 5. Start and Monitor

**Start Service:**
```bash
sudo systemctl start arbitrage-bot
```

**Check Status:**
```bash
sudo systemctl status arbitrage-bot
```

**View Live Logs:**
```bash
sudo journalctl -u arbitrage-bot -f
```

**Monitor Container:**
```bash
docker logs -f arb-bot
```

### 6. Expected Output

Once running, you should see output like:
```
🚀 Starting Solana Arbitrage Bot...
📊 Fetching live market data...
💰 Found 2 profitable opportunities:
  1. Borrowed: 500,000 SOL → Profit: $45,000 @ 95% confidence
     Route: raydium → orca
  2. Borrowed: 250,000 SOL → Profit: $23,000 @ 88% confidence
     Route: orca → jupiter → raydium
✅ Arbitrage executed successfully! Profit: $45,000
```

## Troubleshooting

### Common Issues

**1. Service Won't Start**
```bash
# Check logs
sudo journalctl -u arbitrage-bot --no-pager -n 50

# Check Docker status
sudo docker ps -a

# Restart service
sudo systemctl restart arbitrage-bot
```

**2. No Profitable Opportunities**
```bash
# Lower profit threshold
sudo nano /opt/solana-arbitrage-bot/.env
# Set: MIN_PROFIT_THRESHOLD=1.0

# Restart service
sudo systemctl restart arbitrage-bot
```

**3. RPC Connection Issues**
```bash
# Test RPC connectivity
curl -X POST -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"getHealth"}' \
  https://api.mainnet-beta.solana.com

# Try backup RPC
# Edit .env and change SOLANA_RPC_URL
```

**4. Insufficient SOL Balance**
```bash
# Check wallet balance
solana balance YOUR_WALLET_ADDRESS

# Fund wallet with SOL for gas fees
```

### Performance Optimization

**1. Increase File Limits**
```bash
echo "* soft nofile 65536" >> /etc/security/limits.conf
echo "* hard nofile 65536" >> /etc/security/limits.conf
```

**2. Optimize Network Settings**
```bash
echo "net.core.rmem_max = 16777216" >> /etc/sysctl.conf
echo "net.core.wmem_max = 16777216" >> /etc/sysctl.conf
sysctl -p
```

**3. Enable Swap (if needed)**
```bash
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
```

## Security Considerations

### 1. Firewall Configuration
```bash
# UFW is configured automatically by deploy.sh
# Manual configuration:
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw enable
```

### 2. SSH Security
```bash
# Disable password authentication
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl restart ssh
```

### 3. Fail2Ban (Included in deploy.sh)
```bash
# Check fail2ban status
fail2ban-client status
fail2ban-client status sshd
```

### 4. Private Key Security
- Never commit private keys to version control
- Use environment variables only
- Consider using hardware wallets for production
- Regularly rotate keys

## Monitoring and Alerts

### 1. System Monitoring
```bash
# CPU and Memory usage
htop

# Disk usage
df -h

# Network connections
netstat -tulpn
```

### 2. Application Monitoring
```bash
# Service status
systemctl status arbitrage-bot

# Container stats
docker stats arb-bot

# Application logs
tail -f /var/log/arbitrage-bot/*.log
```

### 3. Profit Monitoring
The bot automatically logs profits:
```bash
# View profit logs
grep "Profit:" /var/log/arbitrage-bot/arbitrage_bot.log
```

### 4. Alerts Setup
Configure webhooks in `.env`:
```bash
# Slack alerts
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK

# Discord alerts
DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/YOUR/DISCORD/WEBHOOK
```

## Maintenance

### 1. Regular Updates
```bash
# Update application
cd /opt/solana-arbitrage-bot
git pull
docker build -t arb-bot:latest .
systemctl restart arbitrage-bot
```

### 2. Log Rotation
```bash
# Logs are automatically rotated by logrotate
# Manual cleanup if needed:
find /var/log/arbitrage-bot -name "*.log" -mtime +7 -delete
```

### 3. Backup Configuration
```bash
# Backup .env file
cp /opt/solana-arbitrage-bot/.env /opt/solana-arbitrage-bot/.env.backup.$(date +%Y%m%d)
```

### 4. Health Checks
```bash
# Automated health check script
/usr/local/bin/arb-bot-monitor
```

## Scaling and Optimization

### 1. Multiple Instances
```bash
# Run multiple instances with different configurations
docker run -d --name arb-bot-1 --env-file .env.config1 arb-bot:latest
docker run -d --name arb-bot-2 --env-file .env.config2 arb-bot:latest
```

### 2. Load Balancing
```bash
# Use nginx for load balancing multiple instances
# Configure upstream servers in nginx.conf
```

### 3. Database Integration
```bash
# Add PostgreSQL for trade history
docker run -d --name postgres \
  -e POSTGRES_DB=arbitrage \
  -e POSTGRES_USER=arbbot \
  -e POSTGRES_PASSWORD=secure_password \
  postgres:13
```

## Support and Resources

- **Documentation**: See README.md for detailed API reference
- **Issues**: Report bugs on GitHub repository
- **Community**: Join Discord/Telegram for support
- **Updates**: Watch repository for new releases

## Cost Estimation

**Monthly VPS Costs:**
- Basic (4GB RAM): $20/month
- Recommended (8GB RAM): $40/month
- High Performance (16GB RAM): $80/month

**Additional Costs:**
- Domain name (optional): $10-15/year
- SSL certificate: Free (Let's Encrypt)
- Monitoring services: $0-50/month

**Expected ROI:**
- With proper configuration: 10-50% monthly returns
- Break-even time: 1-7 days
- Risk level: Medium (with proper risk management)

