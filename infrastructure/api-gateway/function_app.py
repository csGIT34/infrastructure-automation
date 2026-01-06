import azure.functions as func
import logging
import json
import os
from azure.servicebus import ServiceBusClient, ServiceBusMessage
from azure.cosmos import CosmosClient
import yaml
from datetime import datetime
import uuid

app = func.FunctionApp(http_auth_level=func.AuthLevel.FUNCTION)

# Environment variables (set in Function App configuration)
SERVICEBUS_CONNECTION = os.getenv("SERVICE_BUS_CONNECTION")
COSMOS_ENDPOINT = os.getenv("COSMOS_DB_ENDPOINT")
COSMOS_KEY = os.getenv("COSMOS_DB_KEY")
COSMOS_DATABASE = os.getenv("COSMOS_DB_DATABASE", "infrastructure-db")

# Initialize clients lazily to handle cold starts
_servicebus_client = None
_cosmos_container = None

def get_servicebus_client():
    global _servicebus_client
    if _servicebus_client is None and SERVICEBUS_CONNECTION:
        _servicebus_client = ServiceBusClient.from_connection_string(SERVICEBUS_CONNECTION)
    return _servicebus_client

def get_cosmos_container():
    global _cosmos_container
    if _cosmos_container is None and COSMOS_ENDPOINT and COSMOS_KEY:
        cosmos_client = CosmosClient(COSMOS_ENDPOINT, credential=COSMOS_KEY)
        database = cosmos_client.get_database_client(COSMOS_DATABASE)
        _cosmos_container = database.get_container_client("requests")
    return _cosmos_container

@app.route(route="provision", methods=["POST"])
def provision_infrastructure(req: func.HttpRequest) -> func.HttpResponse:
        logging.info('Infrastructure provision request received')

        try:
                req_body = req.get_json()
                yaml_content = req_body.get('yaml_content')
                requester_email = req_body.get('requester_email')

                if not yaml_content or not requester_email:
                        return func.HttpResponse(
                                json.dumps({"error": "Missing required fields"}),
                                status_code=400,
                                mimetype="application/json"
                        )

                try:
                        config = yaml.safe_load(yaml_content)
                except yaml.YAMLError as e:
                        return func.HttpResponse(
                                json.dumps({"error": f"Invalid YAML: {str(e)}"}),
                                status_code=400,
                                mimetype="application/json"
                        )

                validation_result = validate_schema(config)
                if not validation_result['valid']:
                        return func.HttpResponse(
                                json.dumps({"error": "Validation failed", "details": validation_result['errors']}),
                                status_code=400,
                                mimetype="application/json"
                        )

                policy_result = validate_policies(config)
                if not policy_result['valid']:
                        return func.HttpResponse(
                                json.dumps({"error": "Policy validation failed", "details": policy_result['violations']}),
                                status_code=403,
                                mimetype="application/json"
                        )

                estimated_cost = estimate_cost(config)

                request_id = str(uuid.uuid4())
                metadata = config.get('metadata', {})

                request_record = {
                        "id": request_id,
                        "requestId": request_id,  # Partition key
                        "status": "pending",
                        "requester_email": requester_email,
                        "project_name": metadata.get('project_name'),
                        "environment": metadata.get('environment'),
                        "business_unit": metadata.get('business_unit'),
                        "yaml_content": yaml_content,
                        "estimated_cost": estimated_cost,
                        "created_at": datetime.utcnow().isoformat(),
                        "updated_at": datetime.utcnow().isoformat(),
                        "github_run_id": None,
                        "resources": [r.get('type') for r in config.get('resources', [])]
                }

                requests_container = get_cosmos_container()
                if requests_container:
                        requests_container.create_item(request_record)

                queue_name = "infrastructure-requests"  # Single queue for all environments
                servicebus_client = get_servicebus_client()
                if servicebus_client:
                        message = ServiceBusMessage(
                                json.dumps({
                                        "request_id": request_id,
                                        "yaml_content": yaml_content,
                                        "requester_email": requester_email,
                                        "metadata": metadata
                                }),
                                content_type="application/json"
                        )

                        sender = servicebus_client.get_queue_sender(queue_name)
                        sender.send_messages(message)
                        sender.close()

                logging.info(f'Request {request_id} queued successfully')

                return func.HttpResponse(
                        json.dumps({
                                "request_id": request_id,
                                "status": "queued",
                                "estimated_cost": estimated_cost,
                                "queue": queue_name,
                                "tracking_url": f"https://portal.yourcompany.com/requests/{request_id}"
                        }),
                        status_code=202,
                        mimetype="application/json"
                )

        except Exception as e:
                logging.error(f'Error processing request: {str(e)}')
                return func.HttpResponse(
                        json.dumps({"error": "Internal server error"}),
                        status_code=500,
                        mimetype="application/json"
                )

@app.route(route="status/{request_id}", methods=["GET"])
def get_request_status(req: func.HttpRequest) -> func.HttpResponse:
        request_id = req.route_params.get('request_id')
        logging.info(f"Status request for ID: {request_id}")

        try:
                requests_container = get_cosmos_container()
                if not requests_container:
                        logging.error("Cosmos container not initialized")
                        return func.HttpResponse(
                                json.dumps({"error": "Database not configured", "debug": "container_null"}),
                                status_code=503,
                                mimetype="application/json"
                        )

                logging.info(f"Querying Cosmos for ID: {request_id}")
                # Use query to find by id (works without partition key)
                items = list(requests_container.query_items(
                        query="SELECT * FROM c WHERE c.id = @id",
                        parameters=[{"name": "@id", "value": request_id}],
                        enable_cross_partition_query=True
                ))
                logging.info(f"Query returned {len(items)} items")

                if not items:
                        return func.HttpResponse(
                                json.dumps({"error": "Request not found", "debug": "query_empty", "searched_id": request_id}),
                                status_code=404,
                                mimetype="application/json"
                        )

                return func.HttpResponse(
                        json.dumps(items[0]),
                        status_code=200,
                        mimetype="application/json"
                )
        except Exception as e:
                logging.error(f"Error getting status: {str(e)}")
                return func.HttpResponse(
                        json.dumps({"error": "Internal server error", "debug": str(e)}),
                        status_code=500,
                        mimetype="application/json"
                )

def validate_schema(config):
        required_fields = ['metadata', 'resources']
        errors = []

        for field in required_fields:
                if field not in config:
                        errors.append(f"Missing required field: {field}")

        if 'metadata' in config:
                metadata = config['metadata']
                required_metadata = ['project_name', 'environment', 'business_unit', 'cost_center', 'owner_email']
                for field in required_metadata:
                        if field not in metadata:
                                errors.append(f"Missing metadata field: {field}")

        return {"valid": len(errors) == 0, "errors": errors}

def validate_policies(config):
        violations = []
        metadata = config.get('metadata', {})
        environment = metadata.get('environment')

        estimated_cost = estimate_cost(config)
        cost_limits = {'dev': 500, 'staging': 2000, 'prod': 10000}

        if estimated_cost > cost_limits.get(environment, 1000):
                violations.append({
                        "policy": "cost_limit",
                        "severity": "error",
                        "message": f"Cost ${estimated_cost:.2f} exceeds limit"
                })

        return {
                "valid": len([v for v in violations if v['severity'] == 'error']) == 0,
                "violations": violations
        }

def estimate_cost(config):
        cost = 0.0
        cost_map = {
                'postgresql': 25,
                'mongodb': 25,
                'keyvault': 5,
                'eventhub': 25,
                'function_app': 0,
                'linux_vm': 40,
                'storage_account': 5
        }

        for resource in config.get('resources', []):
                cost += cost_map.get(resource.get('type'), 10)

        return cost

@app.route(route="health", methods=["GET"])
def health_check(req: func.HttpRequest) -> func.HttpResponse:
        """Health check endpoint for monitoring"""
        status = {
                "status": "healthy",
                "timestamp": datetime.utcnow().isoformat(),
                "cosmos_configured": COSMOS_ENDPOINT is not None,
                "servicebus_configured": SERVICEBUS_CONNECTION is not None
        }
        return func.HttpResponse(
                json.dumps(status),
                status_code=200,
                mimetype="application/json"
        )
