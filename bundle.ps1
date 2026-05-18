$file = "codebase_context.txt"
if (-not (Test-Path $file)) { Write-Host "Error: codebase_context.txt not found!" -FG Red; exit }
$content = Get-Content $file -Raw
Write-Host "Running advanced DevSecOps deep scan..." -FG Cyan

# 1. Existing Standard Redactions
$content = $content -replace '(?s)-----BEGIN.*?-----.*?-----END.*?-----', '[REDACTED_PRIVATE_KEY]'
$content = $content -replace 'AKIA[A-Z0-9]{16}', '[REDACTED_AWS_KEY_ID]'
$content = $content -replace 'ASIA[A-Z0-9]{16}', '[REDACTED_AWS_SESSION_ID]'
$content = $content -replace '(?i)aws_secret_access_key\s*=\s*"[^"]+"', 'aws_secret_access_key = "[REDACTED_AWS_SECRET]"'

# 2. Cloudflare Specific Redactions (Targets typical Cloudflare token/key variations)
$content = $content -replace '(?i)(cloudflare_api_key|cf_api_key|cloudflare_token|cf_token)\s*=\s*"[^"]+"', '$1 = "[REDACTED_CLOUDFLARE_SECRET]"'

# 3. Catch generic variable assignments containing sensitive string keywords
# This will wipe out anything assigned to words like: token, password, secret, key, credentials
$content = $content -replace '(?i)(token|password|secret|key|cred|credential|pass|passwd)\s*=\s*"[^"]+"', '$1 = "[REDACTED_SENSITIVE_STRING]"'

# 4. Catch high-entropy hex strings (e.g., standard 32-40 character API keys) inside double quotes
$content = $content -replace '"[a-f0-9]{32,45}"', '"[REDACTED_HEX_KEY]"'

Set-Content $file $content
Write-Host "Deep scan complete! File sanitized." -FG Green
