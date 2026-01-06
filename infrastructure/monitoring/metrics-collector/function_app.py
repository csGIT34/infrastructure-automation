import azure.functions as func
import logging
import json
import os
from datetime import datetime, timedelta
from azure.identity import DefaultAzureCredential
from azure.monitor.query import LogsQueryClient
from azure.cosmos import CosmosClient

app = func.FunctionApp()

COSMOS_ENDPOINT = os.getenv("COSMOS_ENDPOINT")
COSMOS_DATABASE = os.getenv("COSMOS_DATABASE", "infrastructure")
LOG_ANALYTICS_WORKSPACE_ID = os.getenv("LOG_ANALYTICS_WORKSPACE_ID")

credential = DefaultAzureCredential()

@app.timer_trigger(schedule="0 */5 * * * *", arg_name="timer", run_on_startup=False)
def collect_metrics(timer: func.TimerRequest) -> None:
    """Collect infrastructure metrics every 5 minutes"""
    logging.info('Collecting infrastructure metrics')

    try:
        metrics = {
            "timestamp": datetime.utcnow().isoformat(),
            "requests": collect_request_metrics(),
            "runners": collect_runner_metrics(),
            "costs": collect_cost_metrics()
        }

        logging.info(f"Metrics collected: {json.dumps(metrics)}")

    except Exception as e:
        logging.error(f"Error collecting metrics: {str(e)}")

def collect_request_metrics():
    """Collect request processing metrics from CosmosDB"""
    try:
        cosmos_client = CosmosClient(COSMOS_ENDPOINT, credential=credential)
        database = cosmos_client.get_database_client(COSMOS_DATABASE)
        container = database.get_container_client("infrastructure-requests")

        # Count requests by status
        query = """
        SELECT c.status, COUNT(1) as count
        FROM c
        WHERE c.created_at >= @start_time
        GROUP BY c.status
        """

        start_time = (datetime.utcnow() - timedelta(hours=24)).isoformat()
        parameters = [{"name": "@start_time", "value": start_time}]

        items = list(container.query_items(
            query=query,
            parameters=parameters,
            enable_cross_partition_query=True
        ))

        return {
            "last_24h": {item["status"]: item["count"] for item in items}
        }
    except Exception as e:
        logging.error(f"Error collecting request metrics: {str(e)}")
        return {}

def collect_runner_metrics():
    """Collect runner metrics from Log Analytics"""
    try:
        logs_client = LogsQueryClient(credential)

        query = """
        KubePodInventory
        | where Namespace == 'github-runners'
        | summarize count() by PodStatus
        """

        response = logs_client.query_workspace(
            workspace_id=LOG_ANALYTICS_WORKSPACE_ID,
            query=query,
            timespan=timedelta(hours=1)
        )

        runner_counts = {}
        for table in response.tables:
            for row in table.rows:
                runner_counts[row[0]] = row[1]

        return runner_counts
    except Exception as e:
        logging.error(f"Error collecting runner metrics: {str(e)}")
        return {}

def collect_cost_metrics():
    """Collect cost metrics from Azure Cost Management"""
    try:
        # Placeholder for cost metrics collection
        # Would integrate with Azure Cost Management API
        return {
            "estimated_daily": 0,
            "estimated_monthly": 0
        }
    except Exception as e:
        logging.error(f"Error collecting cost metrics: {str(e)}")
        return {}

@app.route(route="metrics", methods=["GET"])
def get_metrics(req: func.HttpRequest) -> func.HttpResponse:
    """HTTP endpoint to get current metrics"""
    try:
        metrics = {
            "timestamp": datetime.utcnow().isoformat(),
            "requests": collect_request_metrics(),
            "runners": collect_runner_metrics(),
            "costs": collect_cost_metrics()
        }

        return func.HttpResponse(
            json.dumps(metrics),
            status_code=200,
            mimetype="application/json"
        )
    except Exception as e:
        return func.HttpResponse(
            json.dumps({"error": str(e)}),
            status_code=500,
            mimetype="application/json"
        )

@app.route(route="health", methods=["GET"])
def health_check(req: func.HttpRequest) -> func.HttpResponse:
    """Health check endpoint"""
    return func.HttpResponse(
        json.dumps({"status": "healthy", "timestamp": datetime.utcnow().isoformat()}),
        status_code=200,
        mimetype="application/json"
    )
