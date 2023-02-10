#!/bin/bash

# Tutorial: Getting started with Amazon EMR:
# https://docs.aws.amazon.com/emr/latest/ManagementGuide/emr-gs.html

# do not run all at once! demo script
exit 0

AWS_REGION=us-east-1
AWS_ACCOUNT=`aws sts get-caller-identity --query Account --output text`
EMR_VERSION=emr-5.36.0
#EMR_VERSION=emr-6.3.0
#EMR_VERSION=emr-6.8.0
#EMR_VERSION=emr-6.9.0
EMR_CLUSTER_NAME=$EMR_VERSION-ec2-cluster
SPARK_APP=healthy-food-$RANDOM
S3_BUCKET=emr-$AWS_REGION-$AWS_ACCOUNT
EMR_KEYPAIR=emr-ec2-keypair

# key-pair
aws ec2 create-key-pair \
  --region $AWS_REGION \
  --key-name $EMR_KEYPAIR \
  --query 'KeyMaterial' \
  --output text > $EMR_KEYPAIR.pem &&
chmod 400 $EMR_KEYPAIR.pem

# roles
aws emr create-default-roles --region $AWS_REGION

# subnet
VPC_ID=$(aws ec2 describe-vpcs --region $AWS_REGION \
  --filters Name=is-default,Values=true \
  --query "Vpcs[0].VpcId" --output text)
SUBNET_ID=$(aws ec2 describe-subnets \
  --region $AWS_REGION \
  --filter Name=vpc-id,Values=$VPC_ID \
  --query "Subnets[0].SubnetId" --output text)
echo $SUBNET_ID

# Cluster

# https://awscli.amazonaws.com/v2/documentation/api/latest/reference/emr/create-cluster.html
aws emr create-cluster \
  --region $AWS_REGION \
  --name $EMR_CLUSTER_NAME \
  --release-label $EMR_VERSION \
  --applications Name=Spark \
  --ec2-attributes KeyName=$EMR_KEYPAIR,SubnetId=$SUBNET_ID \
  --instance-fleets \
    InstanceFleetType=MASTER,TargetOnDemandCapacity=1,InstanceTypeConfigs=\['{InstanceType=m4.large}'\] \
    InstanceFleetType=CORE,TargetSpotCapacity=2,InstanceTypeConfigs=\['{InstanceType=m4.large,BidPrice=0.5,WeightedCapacity=3}','{InstanceType=m4.2xlarge,BidPrice=0.9,WeightedCapacity=5}'\],LaunchSpecifications={SpotSpecification='{TimeoutDurationMinutes=10,TimeoutAction=SWITCH_TO_ON_DEMAND}'} \
  --no-auto-terminate \
  --use-default-roles \
  --log-uri s3://$S3_BUCKET/logs/

QUERY=Clusters[?Name==\`$EMR_CLUSTER_NAME\`].Id
EMR_CLUSTER_ID=$(aws emr list-clusters \
  --region $AWS_REGION \
  --active --query=$QUERY --output=text)
echo $EMR_CLUSTER_ID

EMR_CLUSTER_STATE=$(aws emr describe-cluster \
  --region $AWS_REGION \
  --cluster-id $EMR_CLUSTER_ID \
  --query=Cluster.Status.State --output=text)
echo "Is $EMR_CLUSTER_NAME $EMR_CLUSTER_ID ready? $EMR_CLUSTER_STATE"

# Steps

aws s3 cp --region $AWS_REGION food_establishment_data.csv s3://$S3_BUCKET/input/
aws s3 cp --region $AWS_REGION health_violations.py s3://$S3_BUCKET/scripts/

aws emr add-steps \
  --region $AWS_REGION \
  --cluster-id $EMR_CLUSTER_ID \
  --steps "Type=Spark,Name=\"$SPARK_APP\",ActionOnFailure=CONTINUE,Args=[s3://$S3_BUCKET/scripts/health_violations.py,--data_source,s3://$S3_BUCKET/input/food_establishment_data.csv,--output_uri,s3://$S3_BUCKET/output/ec2]"

QUERY=Steps[?Name==\`$SPARK_APP\`].Id
SPARK_STEP=$(aws emr list-steps \
  --region $AWS_REGION \
  --cluster-id $EMR_CLUSTER_ID \
  --query=$QUERY --output=text)

aws emr describe-step  \
  --region $AWS_REGION \
  --cluster-id $EMR_CLUSTER_ID \
  --step-id $SPARK_STEP							

# todo: update security group

aws emr ssh \
  --region $AWS_REGION \
  --cluster-id $EMR_CLUSTER_ID \
  --key-pair-file ./$EMR_KEYPAIR.pem

