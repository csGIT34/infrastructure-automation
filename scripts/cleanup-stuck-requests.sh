#!/bin/bash
# Cleanup stuck infrastructure requests from Service Bus and Cosmos DB
#
# Usage:
#   ./scripts/cleanup-stuck-requests.sh [--dry-run]
#
# Options:
#   --dry-run    Show what would be cleaned up without making changes
#
# Prerequisites:
#   - Azure CLI installed and logged in
#   - Python 3 with azure-servicebus package (pip install azure-servicebus)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=false

# Parse arguments
if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
    echo "=== DRY RUN MODE - No changes will be made ==="
    echo ""
fi

# Configuration
RESOURCE_GROUP="rg-infrastructure-api"
SERVICEBUS_NAMESPACE="sb-infra-api-rrkkz6a8"
COSMOS_ACCOUNT="cosmos-infra-api-rrkkz6a8"
COSMOS_DATABASE="infrastructure-db"
COSMOS_CONTAINER="requests"
QUEUES=("infrastructure-requests-dev" "infrastructure-requests-staging" "infrastructure-requests-prod")

echo "============================================================"
echo "Infrastructure Request Cleanup Script"
echo "============================================================"
echo ""

# Check Azure CLI login
if ! az account show &>/dev/null; then
    echo "ERROR: Not logged into Azure CLI. Run 'az login' first."
    exit 1
fi

echo "Resource Group: $RESOURCE_GROUP"
echo "Service Bus:    $SERVICEBUS_NAMESPACE"
echo "Cosmos DB:      $COSMOS_ACCOUNT"
echo ""

# Get credentials
echo "Fetching credentials..."
SB_CONN=$(az servicebus namespace authorization-rule keys list \
    --namespace-name "$SERVICEBUS_NAMESPACE" \
    --resource-group "$RESOURCE_GROUP" \
    --name RootManageSharedAccessKey \
    --query primaryConnectionString -o tsv)

COSMOS_KEY=$(az cosmosdb keys list \
    --name "$COSMOS_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --query primaryMasterKey -o tsv)

if [[ -z "$SB_CONN" ]] || [[ -z "$COSMOS_KEY" ]]; then
    echo "ERROR: Failed to retrieve credentials"
    exit 1
fi

echo "Credentials retrieved."
echo ""

# Check Service Bus queues
echo "============================================================"
echo "SERVICE BUS QUEUE STATUS"
echo "============================================================"

for queue in "${QUEUES[@]}"; do
    counts=$(az servicebus queue show \
        --namespace-name "$SERVICEBUS_NAMESPACE" \
        --resource-group "$RESOURCE_GROUP" \
        --name "$queue" \
        --query "{active: countDetails.activeMessageCount, dlq: countDetails.deadLetterMessageCount}" \
        -o json 2>/dev/null)

    active=$(echo "$counts" | jq -r '.active')
    dlq=$(echo "$counts" | jq -r '.dlq')

    echo "$queue: $active active, $dlq in DLQ"
done

echo ""

# Create Python cleanup script
CLEANUP_SCRIPT=$(mktemp)
cat > "$CLEANUP_SCRIPT" << 'PYEOF'
import sys
import os
import json
import hmac
import hashlib
import base64
from datetime import datetime, timezone
from urllib.parse import quote
import http.client
import ssl

dry_run = os.environ.get('DRY_RUN', 'false') == 'true'
cosmos_key = os.environ.get('COSMOS_KEY')
sb_conn = os.environ.get('SB_CONN')

# Cosmos DB configuration
cosmos_host = "cosmos-infra-api-rrkkz6a8.documents.azure.com"
database_id = "infrastructure-db"
container_id = "requests"

def get_cosmos_auth(verb, resource_type, resource_id, date):
    key = base64.b64decode(cosmos_key)
    text = f"{verb.lower()}\n{resource_type.lower()}\n{resource_id}\n{date.lower()}\n\n"
    sig = base64.b64encode(hmac.new(key, text.encode('utf-8'), hashlib.sha256).digest()).decode('utf-8')
    return f"type=master&ver=1.0&sig={quote(sig)}"

def query_cosmos(query_text):
    date = datetime.now(timezone.utc).strftime('%a, %d %b %Y %H:%M:%S GMT')
    resource_id = f"dbs/{database_id}/colls/{container_id}"
    auth = get_cosmos_auth("POST", "docs", resource_id, date)

    headers = {
        "Authorization": auth,
        "x-ms-date": date,
        "x-ms-version": "2018-12-31",
        "Content-Type": "application/query+json",
        "x-ms-documentdb-isquery": "true",
        "x-ms-documentdb-query-enablecrosspartition": "true"
    }

    context = ssl.create_default_context()
    conn = http.client.HTTPSConnection(cosmos_host, timeout=30, context=context)
    conn.request("POST", f"/{resource_id}/docs", json.dumps({"query": query_text}), headers)
    response = conn.getresponse()
    data = response.read().decode('utf-8')
    conn.close()

    if response.status == 200:
        return json.loads(data).get('Documents', [])
    return []

def update_cosmos_doc(doc):
    request_id = doc.get('requestId', doc.get('id'))
    doc_resource_id = f"dbs/{database_id}/colls/{container_id}/docs/{doc['id']}"
    date = datetime.now(timezone.utc).strftime('%a, %d %b %Y %H:%M:%S GMT')
    auth = get_cosmos_auth("PUT", "docs", doc_resource_id, date)

    headers = {
        "Authorization": auth,
        "x-ms-date": date,
        "x-ms-version": "2018-12-31",
        "Content-Type": "application/json",
        "x-ms-documentdb-partitionkey": json.dumps([request_id])
    }

    context = ssl.create_default_context()
    conn = http.client.HTTPSConnection(cosmos_host, timeout=30, context=context)
    conn.request("PUT", f"/{doc_resource_id}", json.dumps(doc), headers)
    response = conn.getresponse()
    response.read()
    conn.close()

    return response.status == 200

# Query for stuck records
print("=" * 60)
print("COSMOS DB - STUCK RECORDS")
print("=" * 60)

stuck_records = query_cosmos("SELECT * FROM c WHERE c.status IN ('pending', 'processing', 'queued')")
print(f"Found {len(stuck_records)} stuck records")

for doc in stuck_records:
    request_id = doc.get('requestId', doc.get('id'))
    status = doc.get('status')
    metadata = doc.get('metadata', {})
    project = metadata.get('project_name', 'N/A')

    print(f"\n  ID: {request_id}")
    print(f"  Status: {status}")
    print(f"  Project: {project}")

    if not dry_run:
        doc['status'] = 'failed'
        doc['error'] = 'Cleaned up by admin - stuck in pending state'
        doc['updatedAt'] = datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')

        if update_cosmos_doc(doc):
            print(f"  -> Updated to 'failed'")
        else:
            print(f"  -> FAILED to update")
    else:
        print(f"  -> Would update to 'failed'")

# Clean up Service Bus
print("\n" + "=" * 60)
print("SERVICE BUS - CLEANING QUEUES")
print("=" * 60)

try:
    from azure.servicebus import ServiceBusClient, ServiceBusReceiveMode

    sb_client = ServiceBusClient.from_connection_string(sb_conn)
    queues = ['infrastructure-requests-dev', 'infrastructure-requests-staging', 'infrastructure-requests-prod']

    for queue_name in queues:
        print(f"\n{queue_name}:")

        if dry_run:
            # Peek only
            with sb_client.get_queue_receiver(queue_name, receive_mode=ServiceBusReceiveMode.PEEK_LOCK, max_wait_time=5) as receiver:
                messages = receiver.peek_messages(max_message_count=100)
                if messages:
                    for msg in messages:
                        try:
                            body = json.loads(str(msg))
                            print(f"  Would remove: {body.get('request_id', 'unknown')}")
                        except:
                            print(f"  Would remove: (unparseable message)")
                else:
                    print("  (empty)")
        else:
            # Actually delete
            with sb_client.get_queue_receiver(queue_name, receive_mode=ServiceBusReceiveMode.RECEIVE_AND_DELETE, max_wait_time=10) as receiver:
                messages = receiver.receive_messages(max_message_count=100, max_wait_time=10)
                if messages:
                    for msg in messages:
                        try:
                            body = json.loads(str(msg))
                            print(f"  Removed: {body.get('request_id', 'unknown')}")
                        except:
                            print(f"  Removed: (unparseable message)")
                else:
                    print("  (empty)")

    sb_client.close()

except ImportError:
    print("WARNING: azure-servicebus not installed. Skipping Service Bus cleanup.")
    print("Install with: pip install azure-servicebus")

print("\n" + "=" * 60)
if dry_run:
    print("DRY RUN COMPLETE - No changes were made")
else:
    print("CLEANUP COMPLETE")
print("=" * 60)
PYEOF

# Run the cleanup
export COSMOS_KEY
export SB_CONN
export DRY_RUN=$DRY_RUN

python3 "$CLEANUP_SCRIPT"

# Cleanup temp file
rm -f "$CLEANUP_SCRIPT"

echo ""
echo "Done."
