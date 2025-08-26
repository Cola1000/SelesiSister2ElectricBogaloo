# Assembly HTTP Server Deployment Guide

Disclaimer: Idk if this works, I didn't test it :v

## Installation Steps

### 1. Prepare the System

```bash
# Create deployment directory
sudo mkdir -p /opt/asm-httpd
sudo mkdir -p /opt/asm-httpd/www

# Create www-data user if it doesn't exist
sudo useradd -r -s /bin/false www-data 2>/dev/null || true

# Copy your compiled server
sudo cp httpd /opt/asm-httpd/
sudo chmod +x /opt/asm-httpd/httpd

# Set ownership
sudo chown -R www-data:www-data /opt/asm-httpd
```

### 2. Install Systemd Service

```bash
# Copy the service file
sudo cp asm-httpd.service /etc/systemd/system/

# Reload systemd and enable the service
sudo systemctl daemon-reload
sudo systemctl enable asm-httpd
sudo systemctl start asm-httpd

# Check status
sudo systemctl status asm-httpd
```

### 3. Configure NGINX (Optional but Recommended)

```bash
# Install NGINX if not already installed
sudo apt update && sudo apt install nginx

# Copy the configuration
sudo cp nginx.conf.example /etc/nginx/sites-available/asm-httpd

# Edit the configuration to match your domain
sudo nano /etc/nginx/sites-available/asm-httpd

# Enable the site
sudo ln -s /etc/nginx/sites-available/asm-httpd /etc/nginx/sites-enabled/

# Test configuration
sudo nginx -t

# Reload NGINX
sudo systemctl reload nginx
```

### 4. SSL/HTTPS Setup with Let's Encrypt (Optional)

```bash
# Install certbot
sudo apt install certbot python3-certbot-nginx

# Obtain SSL certificate
sudo certbot --nginx -d your-domain.com -d www.your-domain.com

# Test automatic renewal
sudo certbot renew --dry-run
```

## Management Commands

```bash
# Start the service
sudo systemctl start asm-httpd

# Stop the service  
sudo systemctl stop asm-httpd

# Restart the service
sudo systemctl restart asm-httpd

# View logs
sudo journalctl -u asm-httpd -f

# View NGINX logs
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log
```

## Testing Deployment

```bash
# Test direct connection to Assembly server
curl -v http://localhost:8080/

# Test through NGINX proxy
curl -v http://your-domain.com/

# Test API endpoints
curl -v 'http://your-domain.com/dyn/add?a=2&b=40'

# Test file upload
curl -v --data-binary 'test content' http://your-domain.com/test.txt

# Test authentication
curl -v -u admin:secret http://your-domain.com/auth
```

## Security Considerations

1. **Firewall**: Only allow ports 80 and 443, block direct access to port 8080
2. **User Permissions**: The service runs as `www-data` with minimal privileges
3. **File Permissions**: Web files should be readable but not writable by the service
4. **Rate Limiting**: NGINX configuration includes rate limiting
5. **SSL/TLS**: Use HTTPS in production with strong cipher suites

## Monitoring and Maintenance

1. **Log Rotation**: Ensure log files don't grow too large
2. **Updates**: Recompile and redeploy when making changes
3. **Backups**: Backup your web files and configuration
4. **Health Checks**: Monitor the service status and response times

## Troubleshooting

### Service Won't Start
```bash
# Check service status
sudo systemctl status asm-httpd

# View detailed logs
sudo journalctl -u asm-httpd --no-pager

# Check if port 8080 is in use
sudo netstat -tulpn | grep 8080
```

### NGINX Issues
```bash
# Test configuration
sudo nginx -t

# Check NGINX status
sudo systemctl status nginx

# View error logs
sudo tail -f /var/log/nginx/error.log
```

### Permission Issues
```bash
# Fix ownership
sudo chown -R www-data:www-data /opt/asm-httpd

# Check file permissions
ls -la /opt/asm-httpd/
```