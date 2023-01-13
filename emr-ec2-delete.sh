#!/bin/bash

AWS_REGION=us-east-1
EMR_VERSION=emr-6.8.0
EMR_CLUSTER_NAME=$EMR_VERSION-ec2-cluster

QUERY=Clusters[?Name==\`$EMR_CLUSTER_NAME\`].Id
EMR_CLUSTER_ID=$(aws emr list-clusters \
  --region $AWS_REGION \
  --active --query=$QUERY --output=text)

aws emr terminate-clusters \
  --region $AWS_REGION \
  --cluster-id $EMR_CLUSTER_ID

EMR_CLUSTER_STATE=$(aws emr describe-cluster \
  --region $AWS_REGION \
  --cluster-id $EMR_CLUSTER_ID \
  --query=Cluster.Status.State --output=text)
echo "Is $EMR_CLUSTER_NAME $EMR_CLUSTER_ID ready? $EMR_CLUSTER_STATE"



