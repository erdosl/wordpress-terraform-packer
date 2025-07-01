# WordPress Terraform + Packer Deployment on AWS

This repository builds a custom AMI containing WordPress and supporting components using Packer. The resulting AMI is used by the infrastructure deployment project.

## Project Structure and Execution Order

This project is part of a 3-repository infrastructure setup:

1. [`erdosl/wordpress-terraform-iam`](https://github.com/erdosl/wordpress-terraform-iam)  
   Provisions the IAM roles and policies required to securely run Terraform and EC2 instances.

2. [`erdosl/wordpress-terraform`](https://github.com/erdosl/wordpress-terraform)  
   Deploys the AWS infrastructure then tries to use the AMI - which does not exists yet. So, proceed to step 3. to bake one.
   
3. [`erdosl/wordpress-terraform-packer`](https://github.com/erdosl/wordpress-terraform-packer)  
   Builds a custom AMI containing WordPress, Apache, PHP, and required agents.

> ⚠️ At initial setup, the `wordpress-terraform` deployment will **fail** when trying to find a baked AMI - which is expected - since at that stage there is no baked AMI, yet.
> ⚠️ At the same time, the `packer` project relies on outputs (like EFS ID and subnets) from the `wordpress-terraform` infrastructure to mount persistent storage and configure networking, which means you cannot run the wordpress-terraform-packer without wordpress-terraform.

Make sure to run the repositories in the correct order and run the AMI build after the infrastructure is ready. Currently, the AMI build is manually run.

## Overview

This project builds an AMI containing:

- Apache, PHP, and WordPress core
- SSM and CloudWatch agents
- EFS mount logic

It assumes that networking and EFS infrastructure has already been provisioned by the `wordpress-terraform` project.

---

## Table of Contents

- [Project Overview](#project-overview)  
- [Architecture](#architecture)  
- [Key Features](#key-features)  
- [Modules](#modules)  
- [CI/CD Workflow](#cicd-workflow)  
- [Getting Started](#getting-started)  
- [Requirements](#requirements)  
- [Security Practices](#security-practices)  
- [Credits](#credits)  
- [Contact](#contact)

---

## Project Overview

This repository demonstrates a full DevOps automation pipeline for WordPress on AWS. It showcases real-world use of:

- Infrastructure-as-Code with modular Terraform  
- Immutable infrastructure using Packer  
- CI/CD automation via GitHub Actions and Terraform Cloud  
- Secure and reproducible EC2 environments  
- Self-hosted GitHub Actions runners integrated with AWS  

This project serves both as a functional system and a portfolio artifact to demonstrate cloud-native infrastructure and automation skills.

---

## Architecture

- **Packer** builds a custom AMI with:
  - Apache, PHP, WordPress core  
  - Amazon SSM and CloudWatch agents  
  - EFS mount logic for persistent content  

- **Terraform** provisions:
  - EC2 instances for WordPress and GitHub self-hosted runners  
  - EFS (Elastic File System) for `wp-content`  
  - Application Load Balancer (ALB)  
  - IAM roles and policies  
  - NACLs, security groups, and networking  

- **GitHub Actions** automates:
  - AMI builds using the Packer template  
  - Terraform deployment with updated AMIs  
  - Secure runner execution using self-hosted EC2 instances

---

## Key Features

- Modular Terraform structure with reusable components  
- Full AMI lifecycle with custom provisioning logic  
- Secure, bootstrapped WordPress configuration at runtime  
- GitHub Actions workflow for infrastructure updates  
- Terraform Cloud integration for state and execution  
- Minimal manual steps — infrastructure is fully automated

---

## Modules

- `self-hosted-runner/`: Deploys EC2-based GitHub Actions runner  
- `security-group/`: Configurable SGs for ALB, RDS, EFS, web tier  
- `efs/`: Shared network storage for WordPress media and plugins  
- `load-balancer/`: Application Load Balancer and target group  
- `nacl/`: Custom NACLs for private/public subnets  
- `iam/`: Roles and policies for EC2 and Terraform execution  
- `launch-template/`: (Planned) For future autoscaling integration  

---

## CI/CD Workflow

Defined in `.github/workflows/build-ami.yml`, this workflow:

1. Fetches Terraform outputs via a Python script  
2. Dynamically generates Packer variable file (`github.pkrvars.hcl`)  
3. Builds and tags a new AMI using Packer  
4. Saves the AMI ID into `ami.auto.tfvars`  
5. Triggers deployment to the infrastructure using `terraform apply`

This process uses self-hosted EC2 runners and leverages Terraform Cloud for remote execution and state management.

---

## Getting Started

1. Clone the repository:
    ```bash
    git clone https://github.com/your-org/wordpress-terraform-packer.git
    cd wordpress-terraform-packer
    ```

2. Set required environment variables in GitHub or Terraform Cloud:
    - `TF_VAR_aws_region`  
    - `TF_TOKEN_app_terraform_io`  
    - `TF_VAR_alarm_email`  
    - `TFC_API_READ_TOKEN`  

3. Customize:
    - `packer/wordpress.pkr.hcl` (AMI build)  
    - `userdata_runner.tpl`, `userdata_runtime_wordpress.tpl` (runtime config)  
    - `main.tf` and variables for environment-specific values  

4. Run the GitHub Actions workflow:  
   **"Build WordPress AMI (Self-Hosted)"**

---

## Requirements

- Terraform ≥ 1.12.0  
- AWS Provider ~> 5.98  
- Packer ≥ 1.12.0  
- Python (for the output parsing script)  
- Terraform Cloud account with proper workspace setup  
- AWS account with:
  - OIDC trust for Terraform Cloud  
  - IAM instance profiles for EC2

---

## Security Practices

- IAM policies follow the principle of least privilege  
- EC2 runners and WordPress servers have no public IPs  
- Secrets managed via Terraform Cloud and GitHub Secrets  
- Secure EFS mounting with conditional logic in `user_data`  
- Runtime provisioning handles credentials securely (no plaintext hardcoding)

---

## Credits

This project was built to demonstrate practical DevOps, cloud automation, and infrastructure-as-code workflows for AWS.

---

## Contact

If you're reviewing this for mentorship, hiring, or technical validation, feel free to reach out.

**erdosl**  
GitHub: [github.com/erdosl](https://github.com/erdosl)
