# 1. The Infrastructure Build
Write-Host "--- STARTING FULL REBUILD ---" -ForegroundColor Cyan
terraform apply -auto-approve
if ($LASTEXITCODE -ne 0) { Write-Error "Terraform failed!"; exit }

# 2. Get the new environment details
$IP = terraform output -raw server_ip
$Key = "Keypairforytthumbnail.pem"

# 3. AUTOMATION: Clear the old SSH key automatically
Write-Host "--- CLEANING SSH KNOWN_HOSTS ---" -ForegroundColor Yellow
ssh-keygen -R $IP 2>$null

# 4. AUTOMATION: The "Smart Wait" 
Write-Host "--- WAITING FOR SERVER TO INITIALIZE (DOCKER SETUP) ---" -ForegroundColor Yellow
$ready = $false
$attempts = 0
while (-not $ready -and $attempts -lt 20) {
    Write-Host "." -NoNewline
    ssh -i $Key -o StrictHostKeyChecking=no -o ConnectTimeout=5 ec2-user@$IP "ls /usr/local/bin/docker-compose" 2>$null >$null
    if ($LASTEXITCODE -eq 0) {
        $ready = $true
        Write-Host " Ready!" -ForegroundColor Green
    } else {
        $attempts++
        Start-Sleep -Seconds 10
    }
}

# 5. Run the Deployment
Write-Host "--- STARTING DEPLOYMENT ---" -ForegroundColor Cyan
./deploy.ps1

Write-Host "--- ALL SYSTEMS GO: https://ytthumbnail.site ---" -ForegroundColor Green