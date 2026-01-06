import azure.functions as func
import logging
import json
import os
from azure.identity import DefaultAzureCredential
from azure.servicebus import ServiceBusClient, ServiceBusMessage
from azure.cosmos import CosmosClient
import yaml
from datetime import datetime
import uuid

app = func.FunctionApp(http_auth_level=func.AuthLevel.FUNCTION)

SERVICEBUS_NAMESPACE = os.getenv("SERVICEBUS_NAMESPACE")
COSMOS_ENDPOINT = os.getenv("COSMOS_ENDPOINT")
COSMOS_DATABASE = os.getenv("COSMOS_DATABASE")

credential = DefaultAzureCredential()
servicebus_client = ServiceBusClient(
        f"{SERVICEBUS_NAMESPACE}.servicebus.windows.net",
        credential=credential
)
cosmos_client = CosmosClient(COSMOS_ENDPOINT, credential=credential)
database = cosmos_client.get_database_client(COSMOS_DATABASE)
requests_container = database.get_container_client("infrastructure-requests")

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

                requests_container.create_item(request_record)

                queue_name = get_queue_name(metadata.get('environment'))
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

        try:
                request_record = requests_container.read_item(
                        item=request_id,
                        partition_key=request_id
                )

                return func.HttpResponse(
                        json.dumps(request_record),
                        status_code=200,
                        mimetype="application/json"
                )
        except Exception as e:
                return func.HttpResponse(
                        json.dumps({"error": "Request not found"}),
                        status_code=404,
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

def get_queue_name(environment):
        queue_map = {
                'prod': 'infrastructure-requests-prod',
                'staging': 'infrastructure-requests-staging',
                'dev': 'infrastructure-requests-dev'
        }
        return queue_map.get(environment, 'infrastructure-requests-dev')
