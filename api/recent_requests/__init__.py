import azure.functions as func
import json
import os
import logging
from azure.cosmos import CosmosClient
from azure.identity import DefaultAzureCredential

COSMOS_ENDPOINT = os.environ.get('COSMOS_ENDPOINT', 'https://cosmos-infra-api-rrkkz6a8.documents.azure.com:443/')
COSMOS_DATABASE = os.environ.get('COSMOS_DATABASE', 'infrastructure')
COSMOS_CONTAINER = os.environ.get('COSMOS_CONTAINER', 'infrastructure-requests')

def cors_response(body, status_code=200):
    return func.HttpResponse(
        body=json.dumps(body) if isinstance(body, (dict, list)) else body,
        status_code=status_code,
        mimetype="application/json",
        headers={
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "GET, OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type"
        }
    )

def main(req: func.HttpRequest) -> func.HttpResponse:
    if req.method == "OPTIONS":
        return cors_response("")

    try:
        limit = req.params.get('limit', '10')
        try:
            limit = min(int(limit), 50)
        except:
            limit = 10

        credential = DefaultAzureCredential()
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
