import azure.functions as func
import json
import os
import logging
from azure.servicebus import ServiceBusClient
from azure.servicebus.management import ServiceBusAdministrationClient
from azure.cosmos import CosmosClient
from azure.identity import DefaultAzureCredential

app = func.FunctionApp()

# Configuration from environment variables
SERVICEBUS_NAMESPACE = os.environ.get('SERVICEBUS_NAMESPACE', 'sb-infra-api-rrkkz6a8')
COSMOS_ENDPOINT = os.environ.get('COSMOS_ENDPOINT', 'https://cosmos-infra-api-rrkkz6a8.documents.azure.com:443/')
COSMOS_DATABASE = os.environ.get('COSMOS_DATABASE', 'infrastructure')
COSMOS_CONTAINER = os.environ.get('COSMOS_CONTAINER', 'infrastructure-requests')


def get_credential():
    """Get Azure credential for authentication"""
    return DefaultAzureCredential()


def cors_response(body, status_code=200):
    """Return response with CORS headers"""
    return func.HttpResponse(
        body=json.dumps(body) if isinstance(body, (dict, list)) else body,
        status_code=status_code,
        mimetype="application/json",
        headers={
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type"
        }
    )


@app.function_name(name="queue_status")
@app.route(route="api/queue-status", methods=["GET", "OPTIONS"])
def queue_status(req: func.HttpRequest) -> func.HttpResponse:
    """Get message counts for all infrastructure queues"""

    if req.method == "OPTIONS":
        return cors_response("")

    try:
        credential = get_credential()
        admin_client = ServiceBusAdministrationClient(
            f"{SERVICEBUS_NAMESPACE}.servicebus.windows.net",
            credential=credential
        )

        queues = ['infrastructure-requests-dev', 'infrastructure-requests-staging', 'infrastructure-requests-prod']
        result = {}

        for queue_name in queues:
            try:
                props = admin_client.get_queue_runtime_properties(queue_name)
                env = queue_name.split('-')[-1]
                result[env] = {
                    'active': props.active_message_count,
                    'dead_letter': props.dead_letter_message_count,
                    'scheduled': props.scheduled_message_count,
                    'total': props.total_message_count
                }
            except Exception as e:
                env = queue_name.split('-')[-1]
                result[env] = {'error': str(e)}

        return cors_response(result)

    except Exception as e:
        logging.error(f"Error getting queue status: {e}")
        return cors_response({'error': str(e)}, status_code=500)


@app.function_name(name="request_lookup")
@app.route(route="api/request/{request_id}", methods=["GET", "OPTIONS"])
def request_lookup(req: func.HttpRequest) -> func.HttpResponse:
    """Look up a specific request by ID"""

    if req.method == "OPTIONS":
        return cors_response("")

    request_id = req.route_params.get('request_id')
    if not request_id:
        return cors_response({'error': 'Request ID required'}, status_code=400)

    try:
        credential = get_credential()
        cosmos_client = CosmosClient(COSMOS_ENDPOINT, credential=credential)
        database = cosmos_client.get_database_client(COSMOS_DATABASE)
        container = database.get_container_client(COSMOS_CONTAINER)

        query = "SELECT * FROM c WHERE c.id = @id"
        items = list(container.query_items(
            query=query,
            parameters=[{"name": "@id", "value": request_id}],
            enable_cross_partition_query=True
        ))

        if items:
            return cors_response(items[0])
        else:
            return cors_response({'error': 'Request not found'}, status_code=404)

    except Exception as e:
        logging.error(f"Error looking up request: {e}")
        return cors_response({'error': str(e)}, status_code=500)


@app.function_name(name="recent_requests")
@app.route(route="api/requests/recent", methods=["GET", "OPTIONS"])
def recent_requests(req: func.HttpRequest) -> func.HttpResponse:
    """Get recent infrastructure requests"""

    if req.method == "OPTIONS":
        return cors_response("")

    try:
        limit = req.params.get('limit', '10')
        try:
            limit = min(int(limit), 50)
        except:
            limit = 10

        credential = get_credential()
        cosmos_client = CosmosClient(COSMOS_ENDPOINT, credential=credential)
        database = cosmos_client.get_database_client(COSMOS_DATABASE)
        container = database.get_container_client(COSMOS_CONTAINER)

        query = f"SELECT TOP {limit} * FROM c ORDER BY c._ts DESC"
        items = list(container.query_items(
            query=query,
            enable_cross_partition_query=True
        ))

        return cors_response(items)

    except Exception as e:
        logging.error(f"Error getting recent requests: {e}")
        return cors_response({'error': str(e)}, status_code=500)


@app.function_name(name="health")
@app.route(route="api/health", methods=["GET", "OPTIONS"])
def health(req: func.HttpRequest) -> func.HttpResponse:
    """Health check endpoint"""
    if req.method == "OPTIONS":
        return cors_response("")
    return cors_response({'status': 'healthy', 'service': 'infrastructure-api'})
