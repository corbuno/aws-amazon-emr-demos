#!/bin/bash

# do not run all at once! demo script
exit 0

AWS_REGION=us-east-1
AWS_ACCOUNT=`aws sts get-caller-identity --query Account --output text`
#EMR_VERSION=emr-5.36.0
EMR_VERSION=emr-6.8.0
EMR_CLUSTER_NAME=$EMR_VERSION-ec2-cluster
SPARK_APP=healthy-food-$RANDOM
S3_BUCKET=emr-$AWS_REGION-$AWS_ACCOUNT
EMR_KEYPAIR=emr-ec2-keypair


# key-pair
aws ec2 create-key-pair \
  --key-name $EMR_KEYPAIR \
  --query 'KeyMaterial' \
  --output text > $EMR_KEYPAIR.pem &&
chmod 400 $EMR_KEYPAIR.pem

# roles
aws emr create-default-roles --region $AWS_REGION

# Cluster

# https://docs.aws.amazon.com/cli/latest/reference/emr/create-cluster.html
# https://awscli.amazonaws.com/v2/documentation/api/latest/reference/emr/create-cluster.html
# 2 instances: one master, one core
aws emr create-cluster \
  --region $AWS_REGION \
  --name $EMR_CLUSTER_NAME \
  --release-label $EMR_VERSION \
  --applications Name=JupyterHub Name=Spark Name=Hadoop \
  --ec2-attributes KeyName=$EMR_KEYPAIR \
  --instance-type m5.xlarge --instance-count 2 \
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

