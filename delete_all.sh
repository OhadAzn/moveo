#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <VPC_ID> [REGION]"
  exit 1
fi

VPC_ID="$1"
REGION="${2:-$(aws configure get region 2>/dev/null || echo eu-north-1)}"

export AWS_REGION="$REGION"
export AWS_DEFAULT_REGION="$REGION"

echo "Region: $REGION"
echo "VPC:    $VPC_ID"

INSTANCES=$(aws ec2 describe-instances \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query 'Reservations[].Instances[].InstanceId' --output text 2>/dev/null || true)

if [ -n "${INSTANCES:-}" ] && [ "$INSTANCES" != "None" ]; then
  echo "Terminating instances: $INSTANCES"
  aws ec2 terminate-instances --instance-ids $INSTANCES
  aws ec2 wait instance-terminated --instance-ids $INSTANCES
fi

LB_ARNS=$(aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?VpcId=='$VPC_ID'].LoadBalancerArn" \
  --output text 2>/dev/null || true)

if [ -n "${LB_ARNS:-}" ] && [ "$LB_ARNS" != "None" ]; then
  for LB in $LB_ARNS; do
    echo "Deleting listeners for $LB"
    LISTENERS=$(aws elbv2 describe-listeners \
      --load-balancer-arn "$LB" \
      --query 'Listeners[].ListenerArn' --output text 2>/dev/null || true)
    if [ -n "${LISTENERS:-}" ] && [ "$LISTENERS" != "None" ]; then
      for L in $LISTENERS; do
        aws elbv2 delete-listener --listener-arn "$L"
      done
    fi
    echo "Deleting load balancer $LB"
    aws elbv2 delete-load-balancer --load-balancer-arns "$LB"
  done
  sleep 30
fi

TG_ARNS=$(aws elbv2 describe-target-groups \
  --query "TargetGroups[?VpcId=='$VPC_ID'].TargetGroupArn" \
  --output text 2>/dev/null || true)

if [ -n "${TG_ARNS:-}" ] && [ "$TG_ARNS" != "None" ]; then
  for TG in $TG_ARNS; do
    echo "Deleting target group $TG"
    aws elbv2 delete-target-group --target-group-arn "$TG"
  done
fi

NATS=$(aws ec2 describe-nat-gateways \
  --filter "Name=vpc-id,Values=$VPC_ID" \
  --query 'NatGateways[].NatGatewayId' --output text 2>/dev/null || true)

if [ -n "${NATS:-}" ] && [ "$NATS" != "None" ]; then
  for NGW in $NATS; do
    echo "Deleting NAT gateway $NGW"
    ALLOC=$(aws ec2 describe-nat-gateways \
      --nat-gateway-ids "$NGW" \
      --query 'NatGateways[0].NatGatewayAddresses[0].AllocationId' \
      --output text 2>/dev/null || true)
    aws ec2 delete-nat-gateway --nat-gateway-id "$NGW"
    aws ec2 wait nat-gateway-deleted --nat-gateway-ids "$NGW" || true
    if [ -n "${ALLOC:-}" ] && [ "$ALLOC" != "None" ]; then
      echo "Releasing EIP $ALLOC"
      aws ec2 release-address --allocation-id "$ALLOC" || true
    fi
  done
fi

ENIS=$(aws ec2 describe-network-interfaces \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'NetworkInterfaces[].NetworkInterfaceId' \
  --output text 2>/dev/null || true)

if [ -n "${ENIS:-}" ] && [ "$ENIS" != "None" ]; then
  for ENI in $ENIS; do
    echo "Deleting ENI $ENI"
    aws ec2 delete-network-interface --network-interface-id "$ENI" || true
  done
fi

RTB_ASSO=$(aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'RouteTables[?Associations[?Main==`false`]].Associations[].RouteTableAssociationId' \
  --output text 2>/dev/null || true)

if [ -n "${RTB_ASSO:-}" ] && [ "$RTB_ASSO" != "None" ]; then
  for A in $RTB_ASSO; do
    echo "Disassociate route table association $A"
    aws ec2 disassociate-route-table --association-id "$A" || true
  done
fi

RTBS=$(aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'RouteTables[?Associations[?Main!=`true`]].RouteTableId' \
  --output text 2>/dev/null || true)

if [ -n "${RTBS:-}" ] && [ "$RTBS" != "None" ]; then
  for RT in $RTBS; do
    echo "Deleting route table $RT"
    aws ec2 delete-route-table --route-table-id "$RT" || true
  done
fi

IGW_IDS=$(aws ec2 describe-internet-gateways \
  --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
  --query 'InternetGateways[].InternetGatewayId' \
  --output text 2>/dev/null || true)

if [ -n "${IGW_IDS:-}" ] && [ "$IGW_IDS" != "None" ]; then
  for IGW in $IGW_IDS; do
    echo "Detaching and deleting IGW $IGW"
    aws ec2 detach-internet-gateway --internet-gateway-id "$IGW" --vpc-id "$VPC_ID" || true
    aws ec2 delete-internet-gateway --internet-gateway-id "$IGW" || true
  done
fi

SUBNETS=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'Subnets[].SubnetId' \
  --output text 2>/dev/null || true)

if [ -n "${SUBNETS:-}" ] && [ "$SUBNETS" != "None" ]; then
  for S in $SUBNETS; do
    echo "Deleting subnet $S"
    aws ec2 delete-subnet --subnet-id "$S" || true
  done
fi

SGS=$(aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'SecurityGroups[?GroupName!=`default`].GroupId' \
  --output text 2>/dev/null || true)

if [ -n "${SGS:-}" ] && [ "$SGS" != "None" ]; then
  for SG in $SGS; do
    echo "Deleting security group $SG"
    aws ec2 delete-security-group --group-id "$SG" || true
  done
fi

echo "Deleting VPC $VPC_ID"
aws ec2 delete-vpc --vpc-id "$VPC_ID"
echo "Done."
