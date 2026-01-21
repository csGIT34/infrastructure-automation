# MCP Infrastructure Workflow Generator - Improvement Guide

This document summarizes the issues encountered when using the MCP `generate_workflow` tool and provides recommendations for improving it to match the working production workflow.

## Summary of Issues

The MCP-generated workflow required multiple iterations to work correctly. This document captures all the fixes needed so the `generate_workflow` tool can be improved to produce a working workflow on the first attempt.

---

## Issue 1: Wrong Authentication Method

### Problem
The MCP-generated workflow used HTTP Bearer token authentication:
```yaml
-H "Authorization: Bearer ${API_KEY}"
```

### Solution
The production infrastructure API uses **Azure Service Bus** with SAS token authentication, not a REST API with Bearer tokens.

### Correct Implementation
```python
# Generate SAS token for Service Bus
uri = f"https://{namespace}.servicebus.windows.net/{queue_name}".lower()
expiry = int(time.time()) + 3600
string_to_sign = f"{urllib.parse.quote_plus(uri)}\n{expiry}"
signature = base64.b64encode(
    hmac.new(sas_key.encode('utf-8'), string_to_sign.encode('utf-8'), hashlib.sha256).digest()
).decode('utf-8')
sas_token = f"SharedAccessSignature sr={urllib.parse.quote_plus(uri)}&sig={urllib.parse.quote_plus(signature)}&se={expiry}&skn={sas_key_name}"
```

### Required Secret
- **Old (wrong):** `INFRA_API_KEY`
- **New (correct):** `INFRA_SERVICE_BUS_SAS_KEY`

---

## Issue 2: Wrong Payload Format

### Problem
The MCP-generated workflow sent raw YAML with a simple JSON wrapper:
```python
payload = {
    'yaml_content': yaml_content,
    'requester_email': config['metadata'].get('owner_email')
}
```

### Solution
The Service Bus message requires additional metadata for tracking and processing:

```python
message = {
    'request_id': request_id,
    'yaml_content': yaml_content,
    'requester_email': config['metadata'].get('owner_email', 'gitops@automation'),
    'metadata': {
        'source': 'gitops',
        'repository': repo,
        'commit_sha': os.environ.get('GITHUB_SHA'),
        'triggered_by': os.environ.get('GITHUB_ACTOR'),
        'environment': config['metadata']['environment'],
        'submitted_at': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
    }
}
```

---

## Issue 3: Wrong API Endpoint

### Problem
The MCP-generated workflow called a REST API endpoint:
```python
api_url = f"https://func-infra-api-rrkkz6a8.azurewebsites.net/api/provision?code={api_key}"
```

### Solution
Submit directly to Azure Service Bus queue:
```python
namespace = "sb-infra-api-rrkkz6a8"
queue_name = f"infrastructure-requests-{config['metadata']['environment']}"
url = f"https://{namespace}.servicebus.windows.net/{queue_name}/messages"
```

---

## Issue 4: YAML Syntax Error with Heredoc Strings

### Problem
The MCP-generated workflow used f-strings with triple quotes containing markdown tables:
```python
preview = f"""## Infrastructure Plan Preview

| Property | Value |
|----------|-------|
| Project Name | `{metadata.get('project_name')}` |
```

This caused a YAML parsing error because the `|` character at the start of a line has special meaning in YAML (literal block scalar indicator).

**Error:**
```
yaml.scanner.ScannerError: while scanning a block scalar
expected a comment or a line break, but found 'P'
```

### Solution
Build markdown using `lines.append()` or string concatenation instead of multi-line f-strings:

```python
preview = "## Infrastructure Plan Preview\n\n"
preview += "| Property | Value |\n"
preview += "|----------|-------|\n"
preview += f"| Project Name | `{metadata.get('project_name')}` |\n"
```

Or use the list approach:
```python
lines = []
lines.append("## Infrastructure Plan Preview")
lines.append("")
lines.append("| Property | Value |")
lines.append("|----------|-------|")
lines.append(f"| Project Name | `{metadata.get('project_name')}` |")
preview = "\n".join(lines)
```

---

## Issue 5: Missing Plan API Integration

### Problem
The MCP-generated workflow compared against the git history to determine changes:
```bash
git show origin/${{ github.base_ref }}:infrastructure.yaml > base_infrastructure.yaml
```

### Solution
The production workflow calls a **Plan API** that compares against the last *successful deployment*, not just the git history:

```python
PLAN_API_URL = "https://func-infra-api-rrkkz6a8.azurewebsites.net/api/plan"

response = requests.post(PLAN_API_URL, json={
    'project_name': project,
    'environment': env,
    'proposed_yaml': yaml_content
}, timeout=30)
plan_data = response.json()
```

This provides:
- Comparison against last successful deployment (not just git)
- Accurate resource change detection
- Last deployment metadata (request ID, timestamp)

---

## Issue 6: Missing GitHub App Token for Queue Trigger

### Problem
The provision job needs to trigger the queue consumer in the `infrastructure-automation` repo. This requires a GitHub App token.

### Required Secrets
```yaml
INFRA_APP_ID: GitHub App ID
INFRA_APP_PRIVATE_KEY: GitHub App private key (PEM format)
```

### Implementation
```yaml
- name: Generate GitHub App Token
  id: app-token
  uses: actions/create-github-app-token@v1
  with:
    app-id: ${{ secrets.INFRA_APP_ID }}
    private-key: ${{ secrets.INFRA_APP_PRIVATE_KEY }}
    owner: csGIT34
    repositories: infrastructure-automation

- name: Trigger Queue Consumer
  env:
    GH_TOKEN: ${{ steps.app-token.outputs.token }}
  run: |
    curl -X POST \
      -H "Authorization: token $GH_TOKEN" \
      -H "Accept: application/vnd.github.v3+json" \
      https://api.github.com/repos/csGIT34/infrastructure-automation/dispatches \
      -d '{"event_type":"infrastructure-request","client_payload":{"source":"${{ github.repository }}","sha":"${{ github.sha }}"}}'
```

---

## Issue 7: Missing `azure_sql` in Valid Resource Types

### Problem
The workflow validation rejected `azure_sql` as an invalid resource type.

### Solution
Add `azure_sql` to the valid types list:
```python
valid_types = [
    'storage_account', 'keyvault', 'postgresql', 'mongodb',
    'eventhub', 'function_app', 'linux_vm', 'aks_namespace',
    'static_web_app', 'azure_sql'  # <-- Add this
]
```

---

## Issue 8: Workflow File Extension

### Problem
The MCP tool generated `infrastructure.yml` but the official template uses `infrastructure.yaml`.

### Solution
Use `.yaml` extension to match the official template:
```
.github/workflows/infrastructure.yaml
```

---

## Complete Required Secrets

The workflow requires these GitHub secrets:

| Secret | Description | How to Get |
|--------|-------------|------------|
| `INFRA_SERVICE_BUS_SAS_KEY` | Service Bus SAS key | `az servicebus namespace authorization-rule keys list --namespace-name sb-infra-api-rrkkz6a8 --resource-group rg-infrastructure-api --name RootManageSharedAccessKey --query primaryKey -o tsv` |
| `INFRA_APP_ID` | GitHub App ID | From GitHub App settings |
| `INFRA_APP_PRIVATE_KEY` | GitHub App private key (PEM) | Download from GitHub App settings |

---

## Recommended Changes to MCP `generate_workflow` Tool

### 1. Use the Official Template
Instead of generating a custom workflow, fetch and return the official template:
```
https://raw.githubusercontent.com/csGIT34/infrastructure-automation/main/templates/infrastructure-workflow.yaml
```

### 2. If Generating Custom Workflow

Update the tool to:

1. **Use Service Bus authentication** instead of REST API Bearer tokens
2. **Include full message metadata** (request_id, source, repository, commit_sha, etc.)
3. **Avoid multi-line f-strings with `|` characters** - use string concatenation or list joining
4. **Include the Plan API call** for accurate change detection
5. **Add GitHub App token generation** for queue triggering
6. **Include `azure_sql` in valid resource types**
7. **Use `.yaml` extension** for the workflow file
8. **Document all required secrets** in the workflow header comments

### 3. Output Format

The tool should output:
1. The workflow YAML content
2. Instructions for required secrets
3. Commands to add the secrets via `gh secret set`

---

## Reference: Working Workflow Template

The working workflow template is available at:
```
https://raw.githubusercontent.com/csGIT34/infrastructure-automation/main/templates/infrastructure-workflow.yaml
```

This template should be used as the canonical reference for the `generate_workflow` tool.

---

## Testing Checklist

When testing a generated workflow:

- [ ] YAML syntax is valid (`python -c "import yaml; yaml.safe_load(open('workflow.yaml'))"`)
- [ ] Workflow triggers on `infrastructure.yaml` changes
- [ ] Validation job passes with valid infrastructure.yaml
- [ ] Plan preview is generated and posted to PR
- [ ] Service Bus submission succeeds (201 response)
- [ ] GitHub App token generation succeeds
- [ ] Queue consumer is triggered
- [ ] Request appears in tracking dashboard
