# 1. Sync the website folder
Write-Host "Syncing Website..." -ForegroundColor Cyan
aws s3 sync .\website\ s3://kali-web-lab-kali-12345/ --delete

# 2. Sync the API folder (into an 'api' subfolder in S3)
Write-Host "Syncing API..." -ForegroundColor Cyan
aws s3 sync .\api\ s3://kali-web-lab-kali-12345/api/ --delete

Write-Host "Cloud is now updated!" -ForegroundColor Green
