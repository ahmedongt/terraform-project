$instanceId = (terraform output -raw ec2_instance_id)

if (-not $instanceId -or $instanceId -like "*No outputs found*") {
    Write-Error "Could not retrieve instance ID. Ensure 'terraform apply' has run successfully."
    exit 1
}

$ssmParams = @{
    portNumber = @("3000")
    localPortNumber = @("3000")
}
$jsonString = ConvertTo-Json $ssmParams -Compress
$jsonString | Out-File -FilePath ssm_params.json -Encoding ascii

Write-Host "Launching SSM Tunnel to Instance: $instanceId" -ForegroundColor Green
Write-Host "Grafana URL: http://localhost:3000" -ForegroundColor Cyan

aws ssm start-session --target $instanceId --document-name AWS-StartPortForwardingSession --parameters file://ssm_params.json