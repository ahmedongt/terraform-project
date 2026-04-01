
Write-Host "--- 1. Building the Cloud (Terraform) ---" -ForegroundColor Cyan
terraform apply -auto-approve

Write-Host "--- 2. Filling the S3 Bucket (Code Upload) ---" -ForegroundColor Cyan
.\push_all.ps1

Write-Host "--- DONE! ---" -ForegroundColor Green
Write-Host "The server is now auto-configuring itself in the background."
Write-Host "Give it 2 minutes, then check https://ytthumbnail.site"