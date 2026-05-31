# tunnel.ps1

Write-Host "Fetching the active EC2 Instance ID from local Terraform state..." -ForegroundColor Cyan

# 1. Dynamically extract the raw instance output value directly from your terraform state engine
$INSTANCE_ID = terraform output -raw ec2_instance_id

# 2. Safety Valve: Verify we actually retrieved a valid instance format string
if ([string]::IsNullOrEmpty($INSTANCE_ID) -or $INSTANCE_ID -like "*Error*") {
    Write-Host "❌ Error: Could not retrieve an active Instance ID from Terraform." -ForegroundColor Red
    Write-Host "Ensure your infrastructure is built and you are running this from your project root." -ForegroundColor Yellow
    Exit
}

Write-Host "------------------------------------------------------------" -ForegroundColor Gray
Write-Host "Initializing secure SSM Port Forwarding Tunnel for Grafana (Port 3000)..." -ForegroundColor Cyan
Write-Host "Connecting dynamically to discovered instance: $INSTANCE_ID" -ForegroundColor Green
Write-Host "Keep this window open. Once connected, open your browser and go to http://localhost:3000" -ForegroundColor Yellow
Write-Host "Press Ctrl + C to close the tunnel." -ForegroundColor Magenta
Write-Host "------------------------------------------------------------" -ForegroundColor Gray

# 3. Securely initiate the proxy engine using the dynamically resolved target ID
aws ssm start-session --target $INSTANCE_ID --document-name AWS-StartPortForwardingSession --parameters '{\"portNumber\":[\"3000\"],\"localPortNumber\":[\"3000\"]}'