# Get the IP from Terraform
$IP = terraform output -raw server_ip
$Key = "Keypairforytthumbnail.pem"

Write-Host "--- 1. Syncing Project Files ---" -ForegroundColor Cyan
# Sync files to S3 so the EC2 can pull them
aws s3 sync . s3://kali-web-lab-kali-12345/ --delete --exclude ".terraform/*" --exclude "*.tfstate*" --exclude "venv/*" --exclude "aws/*" --exclude ".git/*"

Write-Host "--- 2. Deploying with Docker Compose ---" -ForegroundColor Cyan
# 1. Sync S3 to local folder
# 2. Use 'down' to clean old containers
# 3. 'export' variables tell Docker to use the classic build engine (avoids buildx errors)
# 4. 'sudo -E' carries those variables into the sudo command
$deployCommand = "sudo aws s3 sync s3://kali-web-lab-kali-12345/ /var/www/html/ && " +
                 "cd /var/www/html/ && " +
                 "sudo /usr/local/bin/docker-compose down --remove-orphans || true && " +
                 "export DOCKER_BUILDKIT=0 && export COMPOSE_DOCKER_CLI_BUILD=0 && " +
                 "sudo -E /usr/local/bin/docker-compose up -d --build"

ssh -i $Key -o StrictHostKeyChecking=no ec2-user@$IP $deployCommand

Write-Host "--- ALL DONE! MISSION ACCOMPLISHED ---" -ForegroundColor Green
Write-Host "Deployment complete via Docker Compose at https://ytthumbnail.site"