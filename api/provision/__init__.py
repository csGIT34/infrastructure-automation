import azure.functions as func
import json
import os
import logging
import yaml
import uuid
from datetime import datetime
from azure.cosmos import CosmosClient
from azure.servicebus import ServiceBusClient, ServiceBusMessage
from azure.identity import DefaultAzureCredential

COSMOS_ENDPOINT = os.environ.get('COSMOS_ENDPOINT', 'https://cosmos-infra-api-rrkkz6a8.documents.azure.com:443/')
COSMOS_DATABASE = os.environ.get('COSMOS_DATABASE', 'infrastructure-db')
COSMOS_CONTAINER = os.environ.get('COSMOS_CONTAINER', 'requests')
SERVICEBUS_NAMESPACE = os.environ.get('SERVICEBUS_NAMESPACE', 'sb-infra-api-rrkkz6a8')

# Cost estimates per resource type (monthly) - base costs
COST_MAP = {
    'postgresql': 25,
    'mongodb': 25,
    'keyvault': 5,
    'eventhub': 25,
    'function_app': 0,
    'linux_vm': 40,
    'storage_account': 5,
    'static_web_app': 0,
    'aks_namespace': 10,
    'azure_sql': 30
}

# SKU-specific pricing overrides
SKU_COSTS = {
    'azure_sql': {
        'Free': 0,
        'Basic': 5,
        'S0': 15,
        'S1': 30,
        'S2': 75,
        'P1': 465,
    },
    'function_app': {
        'Y1': 0,        # Consumption (free)
        'B1': 13,       # Basic
        'S1': 70,       # Standard
        'P1v2': 140,    # Premium
    },
    'postgresql': {
        'B_Standard_B1ms': 25,
        'GP_Standard_D2s_v3': 125,
    }
}

# Free tier SKUs per resource type
FREE_TIER_SKUS = {
    'azure_sql': 'Free',
    'function_app': 'Y1',
    'static_web_app': 'Free',
}

# Cost limits per environment
COST_LIMITS = {
    'dev': 500,
    'staging': 2000,
    'prod': 10000
}

def cors_response(body, status_code=200):
    return func.HttpResponse(
        body=json.dumps(body) if isinstance(body, (dict, list)) else body,
        status_code=status_code,
        mimetype="application/json",
        headers={
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "POST, OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type, x-functions-key"
        }
    )

def estimate_cost(config):
    """Calculate estimated monthly cost for resources based on SKU"""
    cost = 0.0
    for resource in config.get('resources', []):
        rtype = resource.get('type')
        rconfig = resource.get('config', {})
        sku = rconfig.get('sku')

        # Check for SKU-specific pricing
        if rtype in SKU_COSTS and sku in SKU_COSTS[rtype]:
            cost += SKU_COSTS[rtype][sku]
        else:
            cost += COST_MAP.get(rtype, 10)
    return cost

def get_free_tier_recommendations(config):
    """Generate recommendations for using free tiers in dev environments"""
    recommendations = []
    metadata = config.get('metadata', {})
    environment = metadata.get('environment', 'dev')

    # Only recommend free tiers for dev environment
    if environment != 'dev':
        return recommendations

    for resource in config.get('resources', []):
        rtype = resource.get('type')
        rconfig = resource.get('config', {})
        sku = rconfig.get('sku')

        if rtype in FREE_TIER_SKUS:
            free_sku = FREE_TIER_SKUS[rtype]
            if sku != free_sku:
                recommendations.append({
                    "resource": resource.get('name'),
                    "type": rtype,
                    "current_sku": sku or "default",
                    "recommended_sku": free_sku,
                    "message": f"Consider using '{free_sku}' SKU for {rtype} in dev environment (free tier)"
                })

    return recommendations

def validate_schema(config):
    """Validate infrastructure YAML schema"""
    errors = []

    if 'metadata' not in config:
        errors.append("Missing 'metadata' section")
    else:
        metadata = config['metadata']
        required_meta = ['project_name', 'environment', 'business_unit', 'cost_center', 'owner_email']
        for field in required_meta:
            if field not in metadata:
                errors.append(f"Missing metadata.{field}")

    if 'resources' not in config:
        errors.append("Missing 'resources' section")
    elif not isinstance(config.get('resources'), list):
        errors.append("'resources' must be a list")
    elif len(config.get('resources', [])) == 0:
        errors.append("'resources' list is empty")
    else:
        valid_types = ['storage_account', 'keyvault', 'postgresql', 'mongodb',
                       'eventhub', 'function_app', 'linux_vm', 'aks_namespace', 'static_web_app', 'azure_sql']
        for i, resource in enumerate(config['resources']):
            if 'type' not in resource:
                errors.append(f"Resource {i+1}: missing 'type'")
            elif resource['type'] not in valid_types:
                errors.append(f"Resource {i+1}: invalid type '{resource['type']}'. Valid: {', '.join(valid_types)}")
            if 'name' not in resource:
                errors.append(f"Resource {i+1}: missing 'name'")

    return {"valid": len(errors) == 0, "errors": errors}

def validate_policies(config):
    """Validate against cost policies"""
    violations = []
    metadata = config.get('metadata', {})
    environment = metadata.get('environment', 'dev')

    estimated_cost = estimate_cost(config)
    limit = COST_LIMITS.get(environment, 1000)

    if estimated_cost > limit:
        violations.append({
            "policy": "cost_limit",
            "severity": "error",
            "message": f"Estimated cost ${estimated_cost:.2f}/month exceeds {environment} limit of ${limit}"
        })

    return {
        "valid": len([v for v in violations if v['severity'] == 'error']) == 0,
        "violations": violations
    }

def main(req: func.HttpRequest) -> func.HttpResponse:
    if req.method == "OPTIONS":
        return cors_response("")

    logging.info('Infrastructure provision request received')

    try:
        # Parse request body
        try:
            body = req.get_json()
        except ValueError:
            return cors_response({'error': 'Invalid JSON body'}, status_code=400)

        yaml_content = body.get('yaml_content')
        requester_email = body.get('requester_email')

        if not yaml_content or not requester_email:
            return cors_response({
                'error': 'Missing required fields: yaml_content, requester_email'
            }, status_code=400)

        # Parse YAML
        try:
            config = yaml.safe_load(yaml_content)
        except yaml.YAMLError as e:
            return cors_response({'error': f'Invalid YAML: {e}'}, status_code=400)

        # Validate schema
        validation_result = validate_schema(config)
        if not validation_result['valid']:
            return cors_response({
                'error': 'Validation failed',
                'details': validation_result['errors']
            }, status_code=400)

        # Validate policies
        policy_result = validate_policies(config)
        if not policy_result['valid']:
            return cors_response({
                'error': 'Policy validation failed',
                'details': policy_result['violations']
            }, status_code=403)

        # Calculate estimated cost
        estimated_cost = estimate_cost(config)

        # Get free tier recommendations for dev environments
        recommendations = get_free_tier_recommendations(config)

        # Generate request ID
        request_id = str(uuid.uuid4())
        metadata = config.get('metadata', {})
        environment = metadata.get('environment', 'dev')

        # Create request record
        request_record = {
            "id": request_id,
            "requestId": request_id,  # Partition key
            "status": "pending",
            "requester_email": requester_email,
            "project_name": metadata.get('project_name'),
            "environment": environment,
            "business_unit": metadata.get('business_unit'),
            "yaml_content": yaml_content,
            "estimated_cost": estimated_cost,
            "created_at": datetime.utcnow().isoformat(),
            "updated_at": datetime.utcnow().isoformat(),
            "github_run_id": None,
            "resources": [r.get('type') for r in config.get('resources', [])]
        }

        # Store in Cosmos DB
        try:
            credential = DefaultAzureCredential()
            cosmos_client = CosmosClient(COSMOS_ENDPOINT, credential=credential)
            database = cosmos_client.get_database_client(COSMOS_DATABASE)
            container = database.get_container_client(COSMOS_CONTAINER)
            container.create_item(request_record)
            logging.info(f'Created Cosmos DB record for request {request_id}')
        except Exception as e:
            logging.error(f'Failed to create Cosmos DB record: {e}')
            return cors_response({
                'error': 'Failed to store request',
                'details': str(e)
            }, status_code=500)

        # Send to Service Bus
        queue_name = f"infrastructure-requests-{environment}"
        try:
            credential = DefaultAzureCredential()
            servicebus_client = ServiceBusClient(f"{SERVICEBUS_NAMESPACE}.servicebus.windows.net", credential=credential)

            message_body = json.dumps({
                "request_id": request_id,
                "yaml_content": yaml_content,
                "requester_email": requester_email,
                "metadata": metadata
            })

            with servicebus_client.get_queue_sender(queue_name) as sender:
                message = ServiceBusMessage(message_body, content_type="application/json")
                sender.send_messages(message)

            logging.info(f'Sent message to queue {queue_name} for request {request_id}')
        except Exception as e:
            logging.error(f'Failed to send to Service Bus: {e}')
            # Update Cosmos DB status to failed
            try:
                request_record['status'] = 'failed'
                request_record['error'] = f'Failed to queue: {str(e)}'
                container.upsert_item(request_record)
            except:
                pass
            return cors_response({
                'error': 'Failed to queue request',
                'details': str(e)
            }, status_code=500)

        logging.info(f'Request {request_id} queued successfully')

        response_body = {
            'request_id': request_id,
            'status': 'queued',
            'estimated_cost': estimated_cost,
            'queue': queue_name,
            'tracking_url': f'https://wonderful-field-088efae10.1.azurestaticapps.net'
        }

        # Include recommendations if any
        if recommendations:
            response_body['recommendations'] = recommendations

        return cors_response(response_body, status_code=202)

    except Exception as e:
        logging.error(f'Error processing request: {e}')
        return cors_response({
            'error': 'Internal server error',
            'details': str(e)
        }, status_code=500)
