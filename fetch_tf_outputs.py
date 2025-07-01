#!/usr/bin/env python3

# wordpress-terraform-packer/fetch_tf_outputs.py

import subprocess
import json
import os
import sys
import time

# --- Terraform Cloud API Configuration ---
# These are passed as GitHub Actions environment variables/secrets
TFC_ORG_NAME = os.environ.get("TFC_ORG_NAME")
TFC_INFRA_WORKSPACE_ID = os.environ.get("TFC_INFRA_WORKSPACE_ID")
TFC_API_READ_TOKEN = os.environ.get("TFC_API_READ_TOKEN")

# Validate that essential environment variables are set
if not all([TFC_ORG_NAME, TFC_INFRA_WORKSPACE_ID, TFC_API_READ_TOKEN]):
    print("ERROR: Missing one or more TFC_ORG_NAME, TFC_INFRA_WORKSPACE_ID, TFC_API_READ_TOKEN environment variables.", file=sys.stderr)
    print("Please ensure they are set in the job's 'env' block and secrets are correctly linked.", file=sys.stderr)
    sys.exit(1)

TFC_API_BASE_URL = "https://app.terraform.io/api/v2"

# Helper function to make API calls to Terraform Cloud
def get_tfc_api_data(url):
    headers = {
        "Authorization": f"Bearer {TFC_API_READ_TOKEN}",
        "Content-Type": "application/vnd.api+json"
    }
    try:
        print(f"DEBUG: Calling TFC API: {url}")
        # Using curl directly as it's typically available on runners
        curl_cmd = ["curl", "-sS", "-H", f"Authorization: Bearer {TFC_API_READ_TOKEN}", "-H", "Content-Type: application/vnd.api+json", url]
        
        result = subprocess.run(curl_cmd, capture_output=True, text=True, check=True)
        
        # Check for TFC API errors (e.g., 401, 404) if curl didn't already fail on network/DNS
        try:
            response_json = json.loads(result.stdout)
            if 'errors' in response_json:
                print(f"ERROR: TFC API returned errors for {url}: {response_json['errors']}", file=sys.stderr)
                sys.exit(1)
            return response_json
        except json.JSONDecodeError:
            print(f"ERROR: Failed to decode JSON from TFC API response for {url}. Response: {result.stdout}", file=sys.stderr)
            sys.exit(1)
        
    except subprocess.CalledProcessError as e:
        print(f"ERROR: TFC API call to {url} failed with exit code {e.returncode}.", file=sys.stderr)
        print(f"ERROR: Stderr: {e.stderr}", file=sys.stderr)
        print(f"ERROR: Stdout: {e.stdout}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"ERROR: An unexpected error occurred during TFC API call to {url}: {e}", file=sys.stderr)
        sys.exit(1)

# Helper function to run local Terraform commands
def run_tf_command(cmd_parts, check_output=True, timeout=None, input_str=None):
    try:
        print(f"DEBUG: Running Terraform command: {' '.join(cmd_parts)}")
        result = subprocess.run(
            cmd_parts,
            capture_output=True,
            text=True,
            check=check_output,  # Raise an exception if command returns non-zero exit code
            timeout=timeout,     # Timeout for the command
            input=input_str      # Input for commands like 'terraform console'
        )
        print(f"DEBUG: Stdout: {result.stdout}")
        if result.stderr:
            print(f"DEBUG: Stderr: {result.stderr}", file=sys.stderr)
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        print(f"ERROR: Command '{' '.join(e.cmd)}' failed with exit code {e.returncode}.", file=sys.stderr)
        print(f"ERROR: Stderr: {e.stderr}", file=sys.stderr)
        print(f"ERROR: Stdout: {e.stdout}", file=sys.stderr)
        sys.exit(1)
    except subprocess.TimeoutExpired:
        print(f"ERROR: Command '{' '.join(cmd_parts)}' timed out after {timeout} seconds.", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"ERROR: An unexpected error occurred: {e}", file=sys.stderr)
        sys.exit(1)

# --- Main script execution ---
if __name__ == "__main__":
    # 1. Initialize Terraform for the current 'wordpress-terraform-packer' repo's configuration
    print("--- Initializing Terraform in current repo (Python) ---")
    run_tf_command(["terraform", "init", "-no-color"])
    run_tf_command(["terraform", "validate", "-no-color"])
    # This refresh will cause TFC to initiate its refresh/apply logic for this workspace.
    # We are accepting this behavior as it's part of TFC's design for connected workspaces.
    run_tf_command(["terraform", "refresh", "-no-color"]) 

    # 2. Fetch outputs for the self-hosted runner and packer environment from its own state
    # These outputs come from the *current* workspace's outputs, which rely on its data.terraform_remote_state.infra block.
    # The Python script simply reads them AFTER its own 'terraform refresh' has completed.
    print("--- Fetching outputs for the self-hosted runner and packer environment from its own state ---")
    subnet_id = run_tf_command(["terraform", "output", "-raw", "subnet_id"])
    sg_id = run_tf_command(["terraform", "output", "-raw", "security_group_id"])

    # 3. Fetch EFS DNS and VPC ID from the main WordPress infrastructure via TFC API
    # This method is used for outputs needed by Packer (efs_dns_name, vpc_id) to avoid
    # potential conflicts or hangs when the current workspace is in a remote run context.
    print("--- Fetching EFS DNS and VPC ID from the main WordPress infrastructure via TFC API ---")
    
    # Get the latest state version ID for the 'infra' workspace
    state_version_url = f"{TFC_API_BASE_URL}/workspaces/{TFC_INFRA_WORKSPACE_ID}/current-state-version"
    state_version_data = get_tfc_api_data(state_version_url)
    state_version_id = state_version_data['data']['id']
    
    # Get the outputs for that specific state version
    outputs_url = f"{TFC_API_BASE_URL}/state-versions/{state_version_id}/outputs"
    outputs_data = get_tfc_api_data(outputs_url)
    
    # --- Corrected JSON parsing for TFC API outputs ---
    extracted_api_values = {}
    if 'data' in outputs_data and isinstance(outputs_data['data'], list):
        for output_item in outputs_data['data']:
            if 'attributes' in output_item and 'name' in output_item['attributes'] and 'value' in output_item['attributes']:
                extracted_api_values[output_item['attributes']['name']] = output_item['attributes']['value']
            else:
                print(f"WARNING: TFC API output item missing expected attributes: {output_item}", file=sys.stderr)
    else:
        print(f"ERROR: TFC API outputs response 'data' field is not a list or is missing. Response: {json.dumps(outputs_data)}", file=sys.stderr)
        sys.exit(1)

    # Extract specific values using .get() for safety
    efs_dns_name = extracted_api_values.get('efs_dns_name')
    vpc_id = extracted_api_values.get('vpc_id')
    # --- END OF CORRECTED JSON PARSING LOGIC ---

    # Validate that outputs fetched via API are not empty
    if not efs_dns_name or not vpc_id:
        print(f"ERROR: EFS_DNS_NAME ('{efs_dns_name}') or VPC_ID ('{vpc_id}') is empty after TFC API fetch. Check main infra outputs.tf and TFC API token permissions for the 'infra' workspace.", file=sys.stderr)
        sys.exit(1)
    
    print("--- Debug separator after TFC API fetch ---")

    # 4. Final validation that all required outputs are populated
    if not all([subnet_id, sg_id, efs_dns_name, vpc_id]):
        print("ERROR: One or more required environment variables are empty after fetching all outputs (local or API).", file=sys.stderr)
        print(f"  SUBNET_ID: '{subnet_id}'", file=sys.stderr)
        print(f"  SG_ID: '{sg_id}'", file=sys.stderr)
        print(f"  EFS_DNS_NAME: '{efs_dns_name}'", file=sys.stderr)
        print(f"  VPC_ID: '{vpc_id}'", file=sys.stderr)
        sys.exit(1)

    # 5. Set outputs and environment variables for GitHub Actions
    # These print statements will be captured by the GitHub Actions runner
    # to set job-level environment variables (if the step's stdout is redirected).
    # For robust environment variable setting across steps, writing to GITHUB_ENV is primary.
    print(f"SUBNET_ID={subnet_id}")
    print(f"SG_ID={sg_id}")
    print(f"EFS_DNS_NAME={efs_dns_name}")
    print(f"VPC_ID={vpc_id}")

    # For setting step outputs (accessible via steps.fetch_outputs_step.outputs.<output_name>)
    # These MUST be written to the GITHUB_OUTPUT file in recent GitHub Actions versions.
    with open(os.environ.get('GITHUB_OUTPUT', 'temp_github_output.txt'), 'a') as fh:
        print(f"SUBNET_ID={subnet_id}", file=fh)
        print(f"SG_ID={sg_id}", file=fh)
        print(f"EFS_DNS_NAME={efs_dns_name}", file=fh)
        print(f"VPC_ID={vpc_id}", file=fh)

    print("DEBUG: Final fetched outputs sent to GITHUB_ENV and GITHUB_OUTPUT.")
    print(f"  SUBNET_ID: '{subnet_id}'")
    print(f"  SG_ID: '{sg_id}'")
    print(f"  EFS_DNS_NAME: '{efs_dns_name}'")
    print(f"  VPC_ID: '{vpc_id}'")