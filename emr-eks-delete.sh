#!/bin/bash

# do not run all at once! demo script
exit 0

AWS_REGION=us-east-1
EKS_CLUSTER=emr-eks-cluster
EMR_EKS_ROLE_NAME=EMREKSRuntimeRole
POLICY_NAME=EMREKSS3AndLogsAccessPolicy
EKS_CLUSTER=emr-eks-cluster
EMR_K8s_NAMESPACE=emr
EMR_VIRTUAL_CLUSTER=$EKS_CLUSTER-$EMR_K8s_NAMESPACE


# files

rm amazonreview.sql


# virtual cluster

QUERY=virtualClusters[?name==\`$EMR_VIRTUAL_CLUSTER\`].id
EMR_VIRTUAL_CLUSTER_ID=$(aws emr-containers list-virtual-clusters \
  --region $AWS_REGION \
  --query $QUERY --output=text | awk '{print $1;}')
echo $EMR_VIRTUAL_CLUSTER_ID

aws emr-containers delete-virtual-cluster \
  --region $AWS_REGION \
  --id $EMR_VIRTUAL_CLUSTER_ID

# fargate profile and namespace

eksctl delete fargateprofile \
  --region $AWS_REGION \
  --cluster $EKS_CLUSTER \
  --name emr-fargate-profile

kubectl delete namespace $EMR_K8s_NAMESPACE


# role

QUERY=Policies[?PolicyName==\`$POLICY_NAME\`].Arn
POLICY_ARN=$(aws iam list-policies \
  --region $AWS_REGION \
  --scope Local \
  --query $QUERY --output=text)

aws iam detach-role-policy \
  --region $AWS_REGION \
  --role-name $EMR_EKS_ROLE_NAME \
  --policy-arn $POLICY_ARN

aws iam delete-role \
  --region $AWS_REGION \
  --role-name $EMR_EKS_ROLE_NAME 

aws iam delete-policy \
  --region $AWS_REGION \
  --policy-arn $POLICY_ARN

rm emr-eks-access-policy.json


# eks cluster

eksctl delete cluster \
  --region $AWS_REGION \
  --name $EKS_CLUSTER