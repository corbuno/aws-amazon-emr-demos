#!/bin/bash

# do not run all at once! demo script
exit 0

AWS_REGION=us-east-1
AWS_ACCOUNT=`aws sts get-caller-identity --query Account --output text`
#EMR_VERSION=emr-5.36.0
EMR_VERSION=emr-6.9.0
S3_BUCKET=emr-$AWS_REGION-$AWS_ACCOUNT
EMR_SERVERLESS_ROLE_NAME=EMRServerlessS3RuntimeRole
EMR_SERVERLESS_ROLE_ARN=arn:aws:iam::$AWS_ACCOUNT\:role/$EMR_SERVERLESS_ROLE_NAME
EMR_SERVERLESS_SPARK_APP=$EMR_VERSION-serverless-spark-app
EMR_SERVERLESS_HIVE_APP=$EMR_VERSION-serverless-hive-app

# Job Role

aws iam create-role \
  --region $AWS_REGION \
  --role-name $EMR_SERVERLESS_ROLE_NAME \
  --assume-role-policy-document file://emr-serverless-trust-policy.json

cp emr-serverless-access-policy-TEMPLATE.json emr-serverless-access-policy.json
sed -i "" "s|DOC-EXAMPLE-BUCKET|$S3_BUCKET|g" emr-serverless-access-policy.json

POLICY_NAME=EMRServerlessS3AndGlueAccessPolicy
aws iam create-policy \
  --region $AWS_REGION \
  --policy-name $POLICY_NAME \
  --policy-document file://emr-serverless-access-policy.json

QUERY=Policies[?PolicyName==\`$POLICY_NAME\`].Arn
POLICY_ARN=$(aws iam list-policies \
  --region $AWS_REGION \
  --scope Local \
  --query $QUERY --output=text)
echo $POLICY_ARN

aws iam attach-role-policy \
  --region $AWS_REGION \
  --role-name $EMR_SERVERLESS_ROLE_NAME \
  --policy-arn $POLICY_ARN


# Application

aws emr-serverless create-application \
  --region $AWS_REGION \
  --release-label $EMR_VERSION \
  --type "SPARK" \
  --name $EMR_SERVERLESS_SPARK_APP

QUERY=applications[?name==\`$EMR_SERVERLESS_SPARK_APP\`].id
APP_ID=$(aws emr-serverless list-applications \
  --region $AWS_REGION \
  --query $QUERY --output=text)
echo $APP_ID


# Job

aws s3 cp \
  --region $AWS_REGION \
  s3://us-east-1.elasticmapreduce/emr-containers/samples/wordcount/input/ \
  s3://$S3_BUCKET/input/text \
  --recursive

cp wordcount-TEMPLATE.py wordcount.py
sed -i "" "s|EXAMPLE-BUCKET|$S3_BUCKET|g" wordcount.py
aws s3 cp \
  --region $AWS_REGION \
  wordcount.py \
  s3://$S3_BUCKET/scripts/wordcount.py

EMR_SERVERLESS_SPARK_JOB=$EMR_VERSION-serverless-spark-job-$RANDOM
EMR_SERVERLESS_HIVE_JOB=$EMR_VERSION-serverless-hive-job-$RANDOM

aws emr-serverless start-job-run \
  --region $AWS_REGION \
  --application-id $APP_ID \
  --execution-role-arn $EMR_SERVERLESS_ROLE_ARN \
  --name $EMR_SERVERLESS_SPARK_JOB \
  --job-driver "{
    \"sparkSubmit\": {
        \"entryPoint\": \"s3://$S3_BUCKET/scripts/wordcount.py\",
        \"entryPointArguments\": [\"s3://$S3_BUCKET/output/serverless\"],
        \"sparkSubmitParameters\": \"--conf spark.executor.cores=1 --conf spark.executor.memory=4g --conf spark.driver.cores=1 --conf spark.driver.memory=4g --conf spark.executor.instances=1\"
    }}"

QUERY=jobRuns[?name==\`$EMR_SERVERLESS_SPARK_JOB\`].id
JOB_ID=$(aws emr-serverless list-job-runs \
  --region $AWS_REGION \
  --application-id $APP_ID \
  --query $QUERY --output=text)
  echo $JOB_ID

aws emr-serverless get-job-run \
  --region $AWS_REGION \
  --application-id $APP_ID \
  --job-run-id $JOB_ID

# Stop

aws emr-serverless stop-application \
  --region $AWS_REGION \
  --application-id $APP_ID

