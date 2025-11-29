# AWS Infrastructure with Terraform

Simple setup: VPC with public/private subnets, ALB, and EC2 running Nginx in Docker.

## Architecture

```
Internet → ALB (public subnets) → EC2 (private subnet) → Nginx
                                          ↓
                                     NAT Gateway
                                          ↓
                                      Internet
```

## What's deployed

- VPC with 2 public and 2 private subnets
- Internet Gateway for public subnets
- NAT Gateway for EC2 outbound traffic (costs ~$32/month)
- Application Load Balancer in public subnets
- EC2 instance in private subnet (no public IP)
- Nginx running in Docker container on EC2

## Security

- ALB allows port 80 from anywhere
- EC2 only accepts traffic from ALB security group
- EC2 has no public IP
- Private subnets route through NAT, not IGW

## Usage

```bash
terraform init
terraform plan
terraform apply
```

Wait 2-3 minutes for EC2 to install Docker and start Nginx.

Access the app:
```bash
terraform output alb_url
```

Clean up:
```bash
terraform destroy
```

## Variables

Edit these in `variables.tf` if needed:
- aws_region (default: us-east-1)
- vpc_cidr (default: 10.0.0.0/16)
- project (default: moveo)
- environment (default: dev)
- owner (default: ohad)

## Traffic flow

1. Client hits ALB DNS name
2. ALB forwards to target group
3. Target group sends to EC2 on port 80
4. EC2 security group checks source (must be ALB SG)
5. Docker forwards to Nginx container
6. Nginx returns custom HTML

## Cost warning

NAT Gateway is the most expensive part (~$32/month). Everything else is minimal on free tier.
