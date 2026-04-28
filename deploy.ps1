# Get the IP from Terraform
$IP = terraform output -raw server_ip
$Key = "Keypairforytthumbnail.pem"

Write-Host "--- 1. Fast Sync (Only Code) ---" -ForegroundColor Cyan
# Specifically only sync the two folders we need
aws s3 sync ./api s3://kali-web-lab-kali-12345/api/ --delete
aws s3 sync ./website s3://kali-web-lab-kali-12345/website/ --delete

Write-Host "--- 2. Pulling to EC2 & Cleaning ---" -ForegroundColor Cyan
# Pull files from S3 and wipe old containers
ssh -i $Key -o StrictHostKeyChecking=no ec2-user@$IP "sudo aws s3 sync s3://kali-web-lab-kali-12345/ /var/www/html/; docker stop frontend backend || true; docker rm frontend backend || true"

Write-Host "--- 3. Building & Starting API ---" -ForegroundColor Cyan
ssh -i $Key ec2-user@$IP "docker build -t thumb-backend /var/www/html/api/"
ssh -i $Key ec2-user@$IP "docker run -d --name backend -p 5000:5000 thumb-backend"

Write-Host "--- 4. Creating Nginx Proxy Config ---" -ForegroundColor Cyan
# This tells Nginx to route /api requests to the Python container internally
$nginxConf = @"
server {
    listen 80;
    location / {
        root /usr/share/nginx/html;
        index index.html;
    }
    location /api/ {
        proxy_pass http://backend:5000/;
        proxy_set_header Host `$host;
        proxy_set_header X-Real-IP `$remote_addr;
    }
}
"@
# Save the config to the EC2
ssh -i $Key ec2-user@$IP "echo '$nginxConf' | sudo tee /var/www/html/default.conf"

Write-Host "--- 5. Launching Frontend (Secure Mode) ---" -ForegroundColor Cyan
# We link the containers so Nginx can see 'backend' as a hostname
ssh -i $Key ec2-user@$IP "docker run -d --name frontend -p 80:80 --link backend:backend -v /var/www/html/website/index.html:/usr/share/nginx/html/index.html -v /var/www/html/default.conf:/etc/nginx/conf.d/default.conf nginx:alpine"

Write-Host "--- ALL DONE! MISSION ACCOMPLISHED ---" -ForegroundColor Green
Write-Host "Refresh https://ytthumbnail.site and try a link!"