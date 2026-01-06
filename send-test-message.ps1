$REQUEST_ID = "test-" + (Get-Date -Format "yyyyMMddHHmmss")

$yamlContent = @"
metadata:
  project_name: test-project
  environment: dev
  business_unit: engineering
  cost_center: CC-TEST-001
  owner_email: test@example.com
  location: centralus

resources:
  - type: storage_account
    name: testdata
    config:
      tier: Standard
      replication: LRS
"@

$body = @{
    request_id = $REQUEST_ID
    yaml_content = $yamlContent
    requester_email = "test@example.com"
    metadata = @{
        project_name = "test-project"
        environment = "dev"
        business_unit = "engineering"
    }
} | ConvertTo-Json -Compress -Depth 5

Write-Host "Request ID: $REQUEST_ID"
Write-Host "Getting SAS key..."

# Get SAS key
$sasKey = az servicebus namespace authorization-rule keys list --namespace-name sb-infra-api-rrkkz6a8 --resource-group rg-infrastructure-api --name RootManageSharedAccessKey --query primaryKey -o tsv

$endpoint = "sb-infra-api-rrkkz6a8.servicebus.windows.net"
$queueName = "infrastructure-requests-dev"
$sasKeyName = "RootManageSharedAccessKey"

# Generate SAS token - use the queue URI (lowercase)
$uri = "https://$endpoint/$queueName".ToLower()
$expiry = [int]([DateTimeOffset]::UtcNow.AddMinutes(60).ToUnixTimeSeconds())
$encodedUri = [System.Web.HttpUtility]::UrlEncode($uri)
$stringToSign = "$encodedUri`n$expiry"

$hmac = New-Object System.Security.Cryptography.HMACSHA256
$hmac.Key = [Text.Encoding]::UTF8.GetBytes($sasKey)
$signature = [Convert]::ToBase64String($hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($stringToSign)))
$encodedSignature = [System.Web.HttpUtility]::UrlEncode($signature)

$sasToken = "SharedAccessSignature sr=$encodedUri&sig=$encodedSignature&se=$expiry&skn=$sasKeyName"

Write-Host "Sending message..."

# Send message
$headers = @{
    "Authorization" = $sasToken
    "Content-Type" = "application/json"
}

try {
    $response = Invoke-WebRequest -Uri "https://$endpoint/$queueName/messages" -Method Post -Headers $headers -Body $body -UseBasicParsing
    Write-Host "Message sent successfully! Status: $($response.StatusCode)"
    Write-Host "Request ID: $REQUEST_ID"
} catch {
    Write-Host "Error: $($_.Exception.Message)"
    Write-Host "Response: $($_.Exception.Response)"
}
