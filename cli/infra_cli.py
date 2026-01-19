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
import re
from datetime import datetime
from pathlib import Path

API_URL = os.getenv("INFRA_API_URL", "https://func-infra-api.azurewebsites.net")
API_KEY = os.getenv("INFRA_API_KEY", "")

# Find patterns directory (relative to CLI or in repo root)
PATTERNS_DIR = Path(__file__).parent.parent / "patterns"


def get_available_patterns():
    """Load all available patterns from the patterns directory."""
    patterns = {}
    if not PATTERNS_DIR.exists():
        return patterns

    for pattern_dir in PATTERNS_DIR.iterdir():
        if pattern_dir.is_dir():
            pattern_file = pattern_dir / "pattern.yaml"
            if pattern_file.exists():
                with open(pattern_file) as f:
                    patterns[pattern_dir.name] = yaml.safe_load(f)
                    patterns[pattern_dir.name]['path'] = pattern_dir
    return patterns


def render_template(template_content, variables):
    """Replace ${VAR} and ${VAR:default} placeholders with values."""
    def replace_var(match):
        var_expr = match.group(1)
        if ':' in var_expr:
            var_name, default = var_expr.split(':', 1)
        else:
            var_name, default = var_expr, ''
        return variables.get(var_name, default)

    return re.sub(r'\$\{([^}]+)\}', replace_var, template_content)


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


@cli.group()
def patterns():
    """Manage infrastructure patterns."""
    pass


@patterns.command("list")
def patterns_list():
    """List all available infrastructure patterns."""
    available = get_available_patterns()

    if not available:
        click.secho("No patterns found", fg="yellow")
        return

    click.echo("\n" + "=" * 60)
    click.secho("Available Infrastructure Patterns", fg="cyan", bold=True)
    click.echo("=" * 60)

    for name, info in sorted(available.items()):
        click.secho(f"\n  {name}", fg="green", bold=True)
        click.echo(f"    {info.get('description', 'No description')}")

        # Show components
        components = info.get('components', [])
        if components:
            click.echo("    Components:")
            for comp in components:
                click.echo(f"      - {comp.get('type')}: {comp.get('description', '')}")

        # Show estimated costs
        costs = info.get('estimated_costs', {})
        if costs:
            click.echo("    Estimated costs:")
            for env, cost in costs.items():
                click.echo(f"      {env}: ${cost}/month")

    click.echo("\n" + "-" * 60)
    click.echo("Usage: infra init --pattern <pattern-name> --env <environment>")
    click.echo("       infra patterns show <pattern-name>")


@patterns.command("show")
@click.argument("pattern_name")
def patterns_show(pattern_name):
    """Show details of a specific pattern."""
    available = get_available_patterns()

    if pattern_name not in available:
        click.secho(f"Pattern '{pattern_name}' not found", fg="red")
        click.echo("Available patterns: " + ", ".join(available.keys()))
        raise SystemExit(1)

    info = available[pattern_name]
    path = info.get('path')

    click.echo("\n" + "=" * 60)
    click.secho(f"Pattern: {pattern_name}", fg="cyan", bold=True)
    click.echo("=" * 60)
    click.echo(f"\n{info.get('description', 'No description')}")

    # Use cases
    use_cases = info.get('use_cases', [])
    if use_cases:
        click.echo("\nUse cases:")
        for case in use_cases:
            click.echo(f"  - {case}")

    # Components
    components = info.get('components', [])
    if components:
        click.echo("\nComponents:")
        for comp in components:
            click.secho(f"  {comp.get('name')}", fg="green")
            click.echo(f"    Type: {comp.get('type')}")
            click.echo(f"    {comp.get('description', '')}")

    # Available environments
    click.echo("\nAvailable environments:")
    for env in ['dev', 'staging', 'prod']:
        env_file = path / f"{env}.yaml"
        if env_file.exists():
            cost = info.get('estimated_costs', {}).get(env, '?')
            click.echo(f"  - {env} (~${cost}/month)")

    click.echo("\n" + "-" * 60)
    click.echo(f"Initialize: infra init --pattern {pattern_name} --env dev")


@cli.command()
@click.option("--pattern", "-p", help="Pattern to use (run 'infra patterns list' to see options)")
@click.option("--env", "-e", default="dev", help="Environment (dev, staging, prod)")
@click.option("--project", required=True, help="Project name")
@click.option("--business-unit", "-b", required=True, help="Business unit")
@click.option("--cost-center", "-c", required=True, help="Cost center")
@click.option("--email", required=True, help="Owner email")
@click.option("--output", "-o", default="infrastructure.yaml", help="Output file name")
@click.option("--runtime", default="python", help="Runtime for function apps")
@click.option("--runtime-version", default="3.11", help="Runtime version")
@click.option("--location", default="centralus", help="Azure region")
@click.option("--interactive", "-i", is_flag=True, help="Interactive mode")
def init(pattern, env, project, business_unit, cost_center, email, output, runtime, runtime_version, location, interactive):
    """Initialize a new infrastructure configuration.

    Use --pattern to start from a predefined pattern, or --interactive for a wizard.
    """
    available = get_available_patterns()

    # Interactive mode
    if interactive or not pattern:
        if not available:
            click.secho("No patterns available", fg="red")
            raise SystemExit(1)

        click.echo("\n" + "=" * 60)
        click.secho("Infrastructure Setup Wizard", fg="cyan", bold=True)
        click.echo("=" * 60)

        # Select pattern
        click.echo("\nAvailable patterns:")
        pattern_list = list(available.keys())
        for i, name in enumerate(pattern_list, 1):
            desc = available[name].get('description', '')
            cost = available[name].get('estimated_costs', {}).get('dev', '?')
            click.echo(f"  {i}. {name}")
            click.echo(f"     {desc}")
            click.echo(f"     Dev cost: ~${cost}/month")

        choice = click.prompt("\nSelect a pattern", type=int, default=1)
        if 1 <= choice <= len(pattern_list):
            pattern = pattern_list[choice - 1]
        else:
            click.secho("Invalid selection", fg="red")
            raise SystemExit(1)

        # Select environment
        click.echo("\nEnvironments:")
        click.echo("  1. dev (free tier where available)")
        click.echo("  2. staging (basic tier)")
        click.echo("  3. prod (production tier)")
        env_choice = click.prompt("Select environment", type=int, default=1)
        env = ['dev', 'staging', 'prod'][env_choice - 1] if 1 <= env_choice <= 3 else 'dev'

        # Collect other info if not provided
        if not project or project == 'my-project':
            project = click.prompt("Project name")
        if not business_unit or business_unit == 'engineering':
            business_unit = click.prompt("Business unit")
        if not cost_center or cost_center == 'CC-1234':
            cost_center = click.prompt("Cost center")
        if not email or email == 'owner@example.com':
            email = click.prompt("Owner email")

    # Validate pattern
    if pattern not in available:
        click.secho(f"Pattern '{pattern}' not found", fg="red")
        click.echo("Available patterns: " + ", ".join(available.keys()))
        raise SystemExit(1)

    # Load template
    pattern_info = available[pattern]
    pattern_path = pattern_info['path']
    template_file = pattern_path / f"{env}.yaml"

    if not template_file.exists():
        click.secho(f"Environment '{env}' not available for pattern '{pattern}'", fg="red")
        available_envs = [f.stem for f in pattern_path.glob("*.yaml") if f.stem != 'pattern']
        click.echo(f"Available environments: {', '.join(available_envs)}")
        raise SystemExit(1)

    # Read and render template
    with open(template_file) as f:
        template_content = f.read()

    variables = {
        'PROJECT_NAME': project,
        'BUSINESS_UNIT': business_unit,
        'COST_CENTER': cost_center,
        'OWNER_EMAIL': email,
        'RUNTIME': runtime,
        'RUNTIME_VERSION': runtime_version,
        'LOCATION': location,
    }

    rendered = render_template(template_content, variables)

    # Write output
    with open(output, 'w') as f:
        f.write(rendered)

    # Show summary
    estimated_cost = pattern_info.get('estimated_costs', {}).get(env, '?')

    click.echo("\n" + "=" * 60)
    click.secho("Configuration Created!", fg="green", bold=True)
    click.echo("=" * 60)
    click.echo(f"  Pattern:     {pattern}")
    click.echo(f"  Environment: {env}")
    click.echo(f"  Project:     {project}")
    click.echo(f"  Output:      {output}")
    click.echo(f"  Est. Cost:   ~${estimated_cost}/month")

    click.echo("\nNext steps:")
    click.echo(f"  1. Review: cat {output}")
    click.echo(f"  2. Submit: infra provision {output} --email {email}")


if __name__ == "__main__":
    cli()
