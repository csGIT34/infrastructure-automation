import azure.functions as func
import json
import os
import logging
import yaml
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
            "Access-Control-Allow-Methods": "POST, OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type"
        }
    )

def get_resource_key(resource):
    """Generate a unique key for a resource"""
    return f"{resource.get('type')}:{resource.get('name')}"

def get_azure_name(rtype, rname, project, env):
    """Generate expected Azure resource name"""
    if rtype == 'storage_account':
        return f"{project}{rname}{env}".replace('-', '').replace('_', '')[:24]
    elif rtype == 'keyvault':
        return f"{project}-{rname}-{env}"[:24]
    elif rtype == 'postgresql':
        return f"{project}-{rname}-{env}"
    elif rtype == 'static_web_app':
        return f"swa-{project}-{rname}-{env}"
    else:
        return f"{rtype}-{project}-{rname}-{env}"

def compare_resources(proposed_resources, deployed_resources, project, env):
    """Compare proposed vs deployed resources and return diff"""
    proposed_keys = {get_resource_key(r): r for r in proposed_resources}
    deployed_keys = {get_resource_key(r): r for r in deployed_resources}

    proposed_set = set(proposed_keys.keys())
    deployed_set = set(deployed_keys.keys())

    added_keys = proposed_set - deployed_set
    removed_keys = deployed_set - proposed_set
    unchanged_keys = proposed_set & deployed_set

    added = []
    for key in added_keys:
        r = proposed_keys[key]
        added.append({
            'type': r.get('type'),
            'name': r.get('name'),
            'azure_name': get_azure_name(r.get('type'), r.get('name'), project, env)
        })

    removed = []
    for key in removed_keys:
        r = deployed_keys[key]
        removed.append({
            'type': r.get('type'),
            'name': r.get('name'),
            'azure_name': get_azure_name(r.get('type'), r.get('name'), project, env)
        })

    unchanged = []
    for key in unchanged_keys:
        r = proposed_keys[key]
        unchanged.append({
            'type': r.get('type'),
            'name': r.get('name'),
            'azure_name': get_azure_name(r.get('type'), r.get('name'), project, env)
        })

    return {
        'added': added,
        'removed': removed,
        'unchanged': unchanged
    }

def main(req: func.HttpRequest) -> func.HttpResponse:
    if req.method == "OPTIONS":
        return cors_response("")

    try:
        # Parse request body
        try:
            body = req.get_json()
        except ValueError:
            return cors_response({'error': 'Invalid JSON body'}, status_code=400)

        project_name = body.get('project_name')
        environment = body.get('environment')
        proposed_yaml = body.get('proposed_yaml')

        if not all([project_name, environment, proposed_yaml]):
            return cors_response({
                'error': 'Missing required fields: project_name, environment, proposed_yaml'
            }, status_code=400)

        # Parse proposed YAML
        try:
            proposed_config = yaml.safe_load(proposed_yaml)
        except yaml.YAMLError as e:
            return cors_response({'error': f'Invalid YAML: {e}'}, status_code=400)

        proposed_resources = proposed_config.get('resources', [])

        # Query Cosmos DB for last successful deployment
        credential = DefaultAzureCredential()
        cosmos_client = CosmosClient(COSMOS_ENDPOINT, credential=credential)
        database = cosmos_client.get_database_client(COSMOS_DATABASE)
        container = database.get_container_client(COSMOS_CONTAINER)

        # Find last successful deployment for this project/environment
        query = """
            SELECT TOP 1 *
            FROM c
            WHERE c.project_name = @project_name
              AND c.environment = @environment
              AND c.status = 'completed'
            ORDER BY c.completed_at DESC
        """

        items = list(container.query_items(
            query=query,
            parameters=[
                {"name": "@project_name", "value": project_name},
                {"name": "@environment", "value": environment}
            ],
            enable_cross_partition_query=True
        ))

        last_deployment = None
        deployed_resources = []
        warnings = []

        if items:
            last_deployment = {
                'request_id': items[0].get('requestId'),
                'status': items[0].get('status'),
                'deployed_at': items[0].get('completed_at'),
                'requester_email': items[0].get('requester_email')
            }
            deployed_resources = items[0].get('resources', [])
        else:
            warnings.append('No previous successful deployment found. All resources will be created.')

        # Check for recent failed deployments
        failed_query = """
            SELECT TOP 1 *
            FROM c
            WHERE c.project_name = @project_name
              AND c.environment = @environment
              AND c.status = 'failed'
            ORDER BY c.updated_at DESC
        """

        failed_items = list(container.query_items(
            query=failed_query,
            parameters=[
                {"name": "@project_name", "value": project_name},
                {"name": "@environment", "value": environment}
            ],
            enable_cross_partition_query=True
        ))

        if failed_items:
            failed_at = failed_items[0].get('updated_at', 'unknown')
            warnings.append(f'Warning: Last deployment attempt failed at {failed_at}. Actual infrastructure state may differ.')

        # Compare resources
        changes = compare_resources(proposed_resources, deployed_resources, project_name, environment)

        return cors_response({
            'project_name': project_name,
            'environment': environment,
            'last_deployment': last_deployment,
            'changes': changes,
            'summary': {
                'added': len(changes['added']),
                'removed': len(changes['removed']),
                'unchanged': len(changes['unchanged'])
            },
            'warnings': warnings
        })

    except Exception as e:
        logging.error(f"Error generating plan: {e}")
        return cors_response({'error': str(e)}, status_code=500)
