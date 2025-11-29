#!/usr/bin/env bash
set -euo pipefail

REGION="eu-north-1"

echo "Region: ${REGION}"

get_non_default_vpcs() {
  aws ec2 describe-vpcs \
    --region "$REGION" \
    --filters "Name=isDefault,Values=false" \
    --query "Vpcs[].VpcId" \
    --output text
}

for VPC_ID in $(get_non_default_vpcs); do
  echo "==============================="
  echo "Deleting resources in VPC: ${VPC_ID}"
  echo "==============================="

  # 1) Load Balancers (ALB/NLB)
  echo "Finding & deleting load balancers in VPC ${VPC_ID} ..."
  LBS=$(aws elbv2 describe-load-balancers \
    --region "$REGION" \
    --query "LoadBalancers[?VpcId=='${VPC_ID}'].LoadBalancerArn" \
    --output text || true)

  if [[ -n "${LBS}" ]]; then
    for LB_ARN in ${LBS}; do
      echo "  - Deleting LB: ${LB_ARN}"
      aws elbv2 delete-load-balancer \
        --region "$REGION" \
        --load-balancer-arn "$LB_ARN" || true
    done
    echo "Waiting a bit for ALBs to be cleaned up..."
    sleep 30
  fi

  # 2) Target Groups
  echo "Finding & deleting target groups in VPC ${VPC_ID} ..."
  TGS=$(aws elbv2 describe-target-groups \
    --region "$REGION" \
    --query "TargetGroups[?VpcId=='${VPC_ID}'].TargetGroupArn" \
    --output text || true)

  if [[ -n "${TGS}" ]]; then
    for TG_ARN in ${TGS}; do
      echo "  - Deleting TG: ${TG_ARN}"
      aws elbv2 delete-target-group \
        --region "$REGION" \
        --target-group-arn "$TG_ARN" || true
    done
  fi

  # 3) EC2 Instances
  echo "Finding & terminating EC2 instances in VPC ${VPC_ID} ..."
  INSTANCES=$(aws ec2 describe-instances \
    --region "$REGION" \
    --filters "Name=vpc-id,Values=${VPC_ID}" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query "Reservations[].Instances[].InstanceId" \
    --output text || true)

  if [[ -n "${INSTANCES}" ]]; then
    echo "  - Terminating instances: ${INSTANCES}"
    aws ec2 terminate-instances \
      --region "$REGION" \
      --instance-ids ${INSTANCES} || true
    echo "  - Waiting for instances to terminate..."
    aws ec2 wait instance-terminated \
      --region "$REGION" \
      --instance-ids ${INSTANCES} || true
  fi

  # 4) NAT Gateways
  echo "Finding & deleting NAT Gateways in VPC ${VPC_ID} ..."
  NATS=$(aws ec2 describe-nat-gateways \
    --region "$REGION" \
    --filter "Name=vpc-id,Values=${VPC_ID}" \
    --query "NatGateways[].NatGatewayId" \
    --output text || true)
  if [[ -n "${NATS}" ]]; then
    for NAT in ${NATS}; do
      echo "  - Deleting NAT: ${NAT}"
      aws ec2 delete-nat-gateway \
        --region "$REGION" \
        --nat-gateway-id "$NAT" || true
    done
    echo "  - Waiting for NAT Gateways to be deleted..."
    sleep 60
  fi

  # 5) ENIs
  echo "Finding & deleting ENIs in VPC ${VPC_ID} ..."
  ENIS=$(aws ec2 describe-network-interfaces \
    --region "$REGION" \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query "NetworkInterfaces[].NetworkInterfaceId" \
    --output text || true)
  if [[ -n "${ENIS}" ]]; then
    for ENI in ${ENIS}; do
      echo "  - Deleting ENI: ${ENI}"
      aws ec2 delete-network-interface \
        --region "$REGION" \
        --network-interface-id "$ENI" || true
    done
  fi

  # 6) Security Groups (ניקוי rules ואז מחיקה)
  echo "Finding & deleting non-default Security Groups in VPC ${VPC_ID} ..."
  SGS=$(aws ec2 describe-security-groups \
    --region "$REGION" \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query "SecurityGroups[?GroupName!='default'].GroupId" \
    --output text || true)

  if [[ -n "${SGS}" ]]; then
    for SG in ${SGS}; do
      echo "  - Cleaning rules in SG ${SG}"

      INGRESS_JSON=$(aws ec2 describe-security-groups \
        --region "$REGION" \
        --group-ids "$SG" \
        --query "SecurityGroups[0].IpPermissions" \
        --output json)

      if [[ "${INGRESS_JSON}" != "[]" ]]; then
        aws ec2 revoke-security-group-ingress \
          --region "$REGION" \
          --group-id "$SG" \
          --ip-permissions "${INGRESS_JSON}" || true
      fi

      EGRESS_JSON=$(aws ec2 describe-security-groups \
        --region "$REGION" \
        --group-ids "$SG" \
        --query "SecurityGroups[0].IpPermissionsEgress" \
        --output json)

      if [[ "${EGRESS_JSON}" != "[]" ]]; then
        aws ec2 revoke-security-group-egress \
          --region "$REGION" \
          --group-id "$SG" \
          --ip-permissions "${EGRESS_JSON}" || true
      fi

      echo "  - Deleting SG ${SG}"
      aws ec2 delete-security-group \
        --region "$REGION" \
        --group-id "$SG" || true
    done
  fi

  # 7) Route Tables (מנקה routes + מוחק non-main)
  echo "Handling route tables in VPC ${VPC_ID} ..."
  RTBS=$(aws ec2 describe-route-tables \
    --region "$REGION" \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query "RouteTables[].{Id:RouteTableId,Assoc:Associations}" \
    --output json || echo "[]")

  echo "${RTBS}" | jq -c '.[]' | while read -r RT; do
    RT_ID=$(echo "$RT" | jq -r '.Id')
    IS_MAIN=$(echo "$RT" | jq -r '.Assoc[]?.Main // empty')

    ROUTES=$(aws ec2 describe-route-tables \
      --region "$REGION" \
      --route-table-ids "$RT_ID" \
      --query "RouteTables[0].Routes[?Origin=='CreateRoute'].DestinationCidrBlock" \
      --output text || true)

    for R in $ROUTES; do
      echo "    - Deleting route ${R} from RT ${RT_ID}"
      aws ec2 delete-route \
        --region "$REGION" \
        --route-table-id "$RT_ID" \
        --destination-cidr-block "$R" || true
    done

    if [[ "${IS_MAIN}" == "true" ]]; then
      echo "    * Keeping main route table ${RT_ID} (only routes were cleaned)"
    else
      echo "    * Deleting non-main route table ${RT_ID}"
      aws ec2 delete-route-table \
        --region "$REGION" \
        --route-table-id "$RT_ID" || true
    fi
  done

  # 8) Subnets
  echo "Finding & deleting subnets in VPC ${VPC_ID} ..."
  SUBNETS=$(aws ec2 describe-subnets \
    --region "$REGION" \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query "Subnets[].SubnetId" \
    --output text || true)
  if [[ -n "${SUBNETS}" ]]; then
    for SUB in ${SUBNETS}; do
      echo "  - Deleting subnet: ${SUB}"
      aws ec2 delete-subnet \
        --region "$REGION" \
        --subnet-id "$SUB" || true
    done
  fi

  # 9) IGWs
  echo "Finding & detaching/deleting IGWs in VPC ${VPC_ID} ..."
  IGWS=$(aws ec2 describe-internet-gateways \
    --region "$REGION" \
    --filters "Name=attachment.vpc-id,Values=${VPC_ID}" \
    --query "InternetGateways[].InternetGatewayId" \
    --output text || true)
  if [[ -n "${IGWS}" ]]; then
    for IGW in ${IGWS}; do
      echo "  - Detaching & deleting IGW: ${IGW}"
      aws ec2 detach-internet-gateway \
        --region "$REGION" \
        --internet-gateway-id "$IGW" \
        --vpc-id "$VPC_ID" || true
      aws ec2 delete-internet-gateway \
        --region "$REGION" \
        --internet-gateway-id "$IGW" || true
    done
  fi

  # 10) Delete VPC
  echo "Deleting VPC ${VPC_ID} ..."
  aws ec2 delete-vpc \
    --region "$REGION" \
    --vpc-id "$VPC_ID" || true

  echo "Done with VPC ${VPC_ID}"
done

echo "All non-default VPCs and their resources have been processed."
