#!/bin/bash

AWS_REGION=us-east-1
AWS_ACCOUNT=`aws sts get-caller-identity --query Account --output text`
#EMR_VERSION=emr-5.36.0
EMR_VERSION=emr-6.9.0
S3_BUCKET=emr-$AWS_REGION-$AWS_ACCOUNT
EMR_SERVERLESS_ROLE=EMRServerlessS3RuntimeRole
EMR_SERVERLESS_SPARK_APP=$EMR_VERSION-serverless-spark-app
EMR_SERVERLESS_HIVE_APP=$EMR_VERSION-serverless-hive-app

# Application

QUERY=applications[?name==\`$EMR_SERVERLESS_SPARK_APP\`].id
APP_ID=$(aws emr-serverless list-applications \
  --region $AWS_REGION \
  --query $QUERY --output=text)

aws emr-serverless delete-application \
  --region $AWS_REGION \
  --application-id $APP_ID

# Role

QUERY=Policies[?PolicyName==\`$POLICY_NAME\`].Arn
POLICY_ARN=$(aws iam list-policies \
  --region $AWS_REGION \
  --scope Local \
  --query $QUERY --output=text)

aws iam detach-role-policy \
  --region $AWS_REGION \
  --role-name $EMR_SERVERLESS_ROLE \
  --policy-arn $POLICY_ARN

aws iam delete-role \
  --region $AWS_REGION \
  --role-name $EMR_SERVERLESS_ROLE 

aws iam delete-policy \
  --region $AWS_REGION \
  --policy-arn $POLICY_ARN

rm emr-serverless-access-policy.json

# script

rm wordcount.py
