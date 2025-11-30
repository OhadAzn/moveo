# DevOps Home Assignment - Moveo

This project deploys a secure, dockerized Nginx server on AWS using Terraform. The goal is to have a private server that is publicly accessible via a Load Balancer, displaying the message: **"yo this is nginx"**.

## Architecture

The setup is designed for security and high availability:

*   **VPC:** A custom network with 2 Public Subnets and 1 Private Subnets.
*   **Load Balancer (ALB):** Sits in the Public Subnets. It's the only entry point from the internet.
*   **EC2 Instance:** Sits in a Private Subnet. It has no public IP address and cannot be reached directly.
*   **NAT Gateway:** Allows the private EC2 instance to download Docker updates without exposing it to incoming traffic.
*   **Security Groups:** Strict rules ensure the EC2 instance only accepts traffic from the Load Balancer.

## Prerequisites

To run this project, you need:

*   An AWS Account
*   AWS CLI configured locally
*   Terraform installed

## How to Run

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/OhadAzn/moveo.git
    cd moveo
    ```
    terraform init
    ```
    terraform apply
    ```
2.  **Access the App:**
    After the deployment finishes, Terraform will output an `alb_url`.
    Copy and paste that URL into your browser. You should see:
    > **yo this is nginx**

## Docker Setup

The Nginx container is configured automatically using the EC2 `user_data` script.
It pulls the official `nginx:alpine` image and mounts a custom `index.html` file containing our message. The container is set to restart always, ensuring resilience.

## CI/CD (GitHub Actions)

A GitHub Actions workflow is included in `.github/workflows/terraform.yml`.
It automatically triggers on push to the `main` branch:
*   Sets up AWS credentials.
*   Installs Terraform.
*   Runs `terraform init` and `terraform apply`.
