#!/usr/bin/env python3
"""
Infrastructure Self-Service CLI

A command-line tool for requesting and managing infrastructure resources.
"""

import click
import requests
import yaml
import json
import os
from datetime import datetime
from pathlib import Path

API_URL = os.getenv("INFRA_API_URL", "https://func-infra-api.azurewebsites.net")
API_KEY = os.getenv("INFRA_API_KEY", "")


@click.group()
@click.version_option(version="1.0.0")
def cli():
    """Infrastructure Self-Service CLI

    Provision and manage Azure infrastructure resources through a self-service platform.
    """
    pass


@cli.command()
@click.argument("yaml_file", type=click.Path(exists=True))
@click.option("--email", "-e", required=True, help="Requester email address")
@click.option("--dry-run", is_flag=True, help="Validate without submitting")
def provision(yaml_file, email, dry_run):
    """Submit an infrastructure provisioning request.

    YAML_FILE: Path to the infrastructure configuration file.
    """
    try:
        with open(yaml_file, 'r') as f:
            yaml_content = f.read()
            config = yaml.safe_load(yaml_content)
    except yaml.YAMLError as e:
        click.secho(f"Error parsing YAML: {e}", fg="red")
        raise SystemExit(1)

    # Validate required fields
    if 'metadata' not in config:
        click.secho("Error: 'metadata' section is required", fg="red")
        raise SystemExit(1)

    if 'resources' not in config:
        click.secho("Error: 'resources' section is required", fg="red")
        raise SystemExit(1)

    # Display summary
    metadata = config['metadata']
    resources = config['resources']

    click.echo("\n" + "=" * 50)
    click.secho("Infrastructure Request Summary", fg="cyan", bold=True)
    click.echo("=" * 50)
    click.echo(f"Project:      {metadata.get('project_name', 'N/A')}")
    click.echo(f"Environment:  {metadata.get('environment', 'N/A')}")
    click.echo(f"Business Unit: {metadata.get('business_unit', 'N/A')}")
    click.echo(f"Cost Center:  {metadata.get('cost_center', 'N/A')}")
    click.echo(f"Owner:        {metadata.get('owner_email', 'N/A')}")
    click.echo(f"\nResources ({len(resources)}):")
    for r in resources:
        click.echo(f"  - {r.get('type', 'unknown')}: {r.get('name', 'unnamed')}")

    if dry_run:
        click.secho("\n[DRY RUN] Request validated successfully", fg="green")
        return

    if not click.confirm("\nSubmit this request?"):
        click.echo("Cancelled.")
        return

    # Submit request
    try:
        response = requests.post(
            f"{API_URL}/api/provision",
            json={
                "yaml_content": yaml_content,
                "requester_email": email
            },
            headers={
                "x-functions-key": API_KEY,
                "Content-Type": "application/json"
            }
        )

        if response.status_code == 202:
            result = response.json()
            click.secho("\nRequest submitted successfully!", fg="green")
            click.echo(f"Request ID:     {result['request_id']}")
            click.echo(f"Status:         {result['status']}")
            click.echo(f"Estimated Cost: ${result['estimated_cost']:.2f}/month")
            click.echo(f"Queue:          {result['queue']}")
            click.echo(f"\nTrack at: {result['tracking_url']}")
        else:
            error = response.json()
            click.secho(f"\nError: {error.get('error', 'Unknown error')}", fg="red")
            if 'details' in error:
                for detail in error['details']:
                    click.echo(f"  - {detail}")
            raise SystemExit(1)

    except requests.RequestException as e:
        click.secho(f"\nConnection error: {e}", fg="red")
        raise SystemExit(1)


@cli.command()
@click.argument("request_id")
def status(request_id):
    """Check the status of a provisioning request.

    REQUEST_ID: The unique identifier of the request.
    """
    try:
        response = requests.get(
            f"{API_URL}/api/status/{request_id}",
            headers={"x-functions-key": API_KEY}
        )

        if response.status_code == 200:
            result = response.json()

            click.echo("\n" + "=" * 50)
            click.secho("Request Status", fg="cyan", bold=True)
            click.echo("=" * 50)
            click.echo(f"Request ID:   {result['id']}")

            status_color = {
                'pending': 'yellow',
                'processing': 'blue',
                'completed': 'green',
                'failed': 'red'
            }.get(result['status'], 'white')

            click.echo(f"Status:       ", nl=False)
            click.secho(result['status'].upper(), fg=status_color, bold=True)

            click.echo(f"Project:      {result.get('project_name', 'N/A')}")
            click.echo(f"Environment:  {result.get('environment', 'N/A')}")
            click.echo(f"Created:      {result.get('created_at', 'N/A')}")
            click.echo(f"Updated:      {result.get('updated_at', 'N/A')}")

            if result.get('github_run_url'):
                click.echo(f"\nGitHub Run:   {result['github_run_url']}")

            if result.get('terraform_outputs'):
                click.echo("\nOutputs:")
                for key, value in result['terraform_outputs'].items():
                    click.echo(f"  {key}: {value.get('value', 'N/A')}")

        elif response.status_code == 404:
            click.secho(f"\nRequest not found: {request_id}", fg="red")
            raise SystemExit(1)
        else:
            click.secho(f"\nError checking status", fg="red")
            raise SystemExit(1)

    except requests.RequestException as e:
        click.secho(f"\nConnection error: {e}", fg="red")
        raise SystemExit(1)


@cli.command()
@click.option("--business-unit", "-b", help="Filter by business unit")
@click.option("--environment", "-e", help="Filter by environment")
@click.option("--status", "-s", help="Filter by status")
@click.option("--limit", "-n", default=10, help="Number of results to show")
def list(business_unit, environment, status, limit):
    """List recent infrastructure requests."""
    click.secho("Listing recent requests...", fg="cyan")
    click.echo("(Feature coming soon - queries CosmosDB for request history)")


@cli.command()
def templates():
    """Show available infrastructure templates."""
    templates_info = [
        {
            "name": "web-app-stack",
            "description": "Web application with PostgreSQL, KeyVault, and Storage",
            "resources": ["postgresql", "keyvault", "storage_account"]
        },
        {
            "name": "data-pipeline",
            "description": "Data processing pipeline with EventHub and Functions",
            "resources": ["eventhub", "function_app", "storage_account"]
        },
        {
            "name": "microservices",
            "description": "Microservices setup with AKS namespace and MongoDB",
            "resources": ["aks_namespace", "mongodb", "keyvault"]
        }
    ]

    click.echo("\n" + "=" * 50)
    click.secho("Available Templates", fg="cyan", bold=True)
    click.echo("=" * 50)

    for t in templates_info:
        click.secho(f"\n{t['name']}", fg="green", bold=True)
        click.echo(f"  {t['description']}")
        click.echo(f"  Resources: {', '.join(t['resources'])}")

    click.echo(f"\nFind templates in: examples/")


@cli.command()
@click.argument("template_name")
@click.option("--output", "-o", default="infrastructure.yaml", help="Output file name")
def init(template_name, output):
    """Initialize a new infrastructure configuration from a template.

    TEMPLATE_NAME: Name of the template to use.
    """
    templates = {
        "web-app-stack": {
            "metadata": {
                "project_name": "my-web-app",
                "environment": "dev",
                "business_unit": "engineering",
                "cost_center": "CC-1234",
                "owner_email": "owner@company.com"
            },
            "resources": [
                {
                    "type": "postgresql",
                    "name": "main-db",
                    "config": {
                        "sku": "B_Standard_B1ms",
                        "storage_mb": 32768,
                        "version": "14"
                    }
                },
                {
                    "type": "keyvault",
                    "name": "secrets",
                    "config": {
                        "sku": "standard"
                    }
                },
                {
                    "type": "storage_account",
                    "name": "data",
                    "config": {
                        "tier": "Standard",
                        "replication": "LRS",
                        "containers": [
                            {"name": "uploads"},
                            {"name": "static"}
                        ]
                    }
                }
            ]
        }
    }

    if template_name not in templates:
        click.secho(f"Template '{template_name}' not found", fg="red")
        click.echo("Available templates: " + ", ".join(templates.keys()))
        raise SystemExit(1)

    template = templates[template_name]

    with open(output, 'w') as f:
        yaml.dump(template, f, default_flow_style=False, sort_keys=False)

    click.secho(f"Created {output} from template '{template_name}'", fg="green")
    click.echo("Edit the file and run: infra provision <file> --email <your-email>")


if __name__ == "__main__":
    cli()
