# tunnel.ps1

Write-Host "Fetching an active, running EC2 Instance ID directly from AWS live API..." -ForegroundColor Cyan

# 1. Dynamically query AWS for a running instance tagged as 'asg-app-instance'
$INSTANCE_ID = aws ec2 describe-instances `
    --filters "Name=tag:Name,Values=asg-app-instance" "Name=instance-state-name,Values=running" `
    --query "Reservations[0].Instances[0].InstanceId" `
    --output text

# 2. Safety Valve: Verify we actually retrieved a valid instance format string (starts with i-)
if ([string]::IsNullOrEmpty($INSTANCE_ID) -or $INSTANCE_ID -eq "None" -or $INSTANCE_ID -notlike "i-*") {
    Write-Host "❌ Error: Could not find any active, running EC2 instances tagged 'asg-app-instance'." -ForegroundColor Red
    Write-Host "Ensure your Auto Scaling Group has successfully spun up your instances and they are healthy." -ForegroundColor Yellow
    Exit
}

Write-Host "------------------------------------------------------------" -ForegroundColor Gray
Write-Host "Initializing secure SSM Port Forwarding Tunnel for Grafana (Port 3000)..." -ForegroundColor Cyan
Write-Host "Connecting dynamically to discovered instance: $INSTANCE_ID" -ForegroundColor Green
Write-Host "Keep this window open. Once connected, open your browser and go to http://localhost:3000" -ForegroundColor Yellow
Write-Host "Press Ctrl + C to close the tunnel." -ForegroundColor Magenta
Write-Host "------------------------------------------------------------" -ForegroundColor Gray

# 3. Securely initiate the proxy engine using the dynamically resolved live target ID
aws ssm start-session --target $INSTANCE_ID --document-name AWS-StartPortForwardingSession --parameters '{\"portNumber\":[\"3000\"],\"localPortNumber\":[\"3000\"]}'