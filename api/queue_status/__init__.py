import azure.functions as func
import json
import os
import logging
import traceback

SERVICEBUS_NAMESPACE = os.environ.get('SERVICEBUS_NAMESPACE', 'sb-infra-api-rrkkz6a8')

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
        from azure.servicebus.management import ServiceBusAdministrationClient
        from azure.identity import DefaultAzureCredential

        credential = DefaultAzureCredential()
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
        logging.error(traceback.format_exc())
        return cors_response({'error': str(e), 'traceback': traceback.format_exc()}, status_code=500)
