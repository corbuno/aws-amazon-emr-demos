#!/bin/bash

# do not run all at once! demo script
exit 0

AWS_REGION=us-east-1
AWS_ACCOUNT=`aws sts get-caller-identity --query Account --output text`
#EMR_VERSION=emr-5.36.0
EMR_VERSION=emr-6.8.0
EKS_CLUSTER=emr-eks-cluster
EMR_K8s_NAMESPACE=emr
EMR_EKS_ROLE_NAME=EMREKSRuntimeRole
EMR_EKS_ROLE_ARN=arn:aws:iam::$AWS_ACCOUNT\:role/$EMR_EKS_ROLE_NAME
EMR_VIRTUAL_CLUSTER=$EKS_CLUSTER-$EMR_K8s_NAMESPACE
S3_BUCKET=emr-$AWS_REGION-$AWS_ACCOUNT
POLICY_NAME=EMREKSS3AndLogsAccessPolicy

# Set up an Amazon EKS cluster

# Create cluster with Fargate and no EC2 instances
eksctl create cluster \
  --region $AWS_REGION \
  --zones "$AWS_REGION"a,"$AWS_REGION"b \
  --name $EKS_CLUSTER \
  --version 1.24 \
  --fargate --without-nodegroup

eksctl utils update-cluster-logging \
  --region $AWS_REGION \
  --enable-types all \
  --cluster $EKS_CLUSTER \
  --approve

kubectl create namespace $EMR_K8s_NAMESPACE
eksctl create fargateprofile \
  --region $AWS_REGION \
  --cluster $EKS_CLUSTER \
  --name emr-fargate-profile \
  --namespace $EMR_K8s_NAMESPACE

kubectl get nodes -o wide

kubectl get pods --all-namespaces -o wide

# Enable cluster access for Amazon EMR on EKS

eksctl create iamidentitymapping \
  --region $AWS_REGION \
  --cluster $EKS_CLUSTER \
  --namespace $EMR_K8s_NAMESPACE \
  --service-name "emr-containers"

# Create a Kubernetes role in a specific namespace
cat - <<EOF | kubectl apply -f - --namespace "${EMR_K8s_NAMESPACE}"
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: emr-containers
  namespace: ${EMR_K8s_NAMESPACE}
rules:
  - apiGroups: [""]
    resources: ["namespaces"]
    verbs: ["get"]
  - apiGroups: [""]
    resources: ["serviceaccounts", "services", "configmaps", "events", "pods", "pods/log"]
    verbs: ["get", "list", "watch", "describe", "create", "edit", "delete", "deletecollection", "annotate", "patch", "label"]
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["create", "patch", "delete", "watch"]
  - apiGroups: ["apps"]
    resources: ["statefulsets", "deployments"]
    verbs: ["get", "list", "watch", "describe", "create", "edit", "delete", "annotate", "patch", "label"]
  - apiGroups: ["batch"]
    resources: ["jobs"]
    verbs: ["get", "list", "watch", "describe", "create", "edit", "delete", "annotate", "patch", "label"]
  - apiGroups: ["extensions"]
    resources: ["ingresses"]
    verbs: ["get", "list", "watch", "describe", "create", "edit", "delete", "annotate", "patch", "label"]
  - apiGroups: ["rbac.authorization.k8s.io"]
    resources: ["roles", "rolebindings"]
    verbs: ["get", "list", "watch", "describe", "create", "edit", "delete", "deletecollection", "annotate", "patch", "label"]
EOF

# Create a Kubernetes role binding scoped to the namespace
cat - <<EOF | kubectl apply -f - --namespace "${EMR_K8s_NAMESPACE}"
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: emr-containers
  namespace: ${EMR_K8s_NAMESPACE}
subjects:
- kind: User
  name: emr-containers
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: emr-containers
  apiGroup: rbac.authorization.k8s.io
EOF

# Update Kubernetes aws-auth conﬁguration map
eksctl create iamidentitymapping \
  --region $AWS_REGION \
  --cluster $EKS_CLUSTER \
  --arn "arn:aws:iam::$AWS_ACCOUNT\:role/AWSServiceRoleForAmazonEMRContainers" \
  --username emr-containers


# Enable IAM Roles for Service Accounts (IRSA) on the EKS cluster

aws eks describe-cluster \
  --region $AWS_REGION \
  --name $EKS_CLUSTER \
  --query "cluster.identity.oidc.issuer" --output text

# create an IAM OIDC identity provider for your cluster
eksctl utils associate-iam-oidc-provider \
  --region $AWS_REGION \
  --cluster $EKS_CLUSTER \
  --approve

# Create a job execution role

aws iam create-role \
  --region $AWS_REGION \
  --role-name $EMR_EKS_ROLE_NAME \
  --assume-role-policy-document file://emr-eks-trust-policy.json

cp emr-eks-access-policy-TEMPLATE.json emr-eks-access-policy.json
sed -i "" "s|EXAMPLE-BUCKET|$S3_BUCKET|g" emr-eks-access-policy.json

aws iam create-policy \
  --region $AWS_REGION \
  --policy-name $POLICY_NAME \
  --policy-document file://emr-eks-access-policy.json

QUERY=Policies[?PolicyName==\`$POLICY_NAME\`].Arn
POLICY_ARN=$(aws iam list-policies \
  --region $AWS_REGION \
  --scope Local \
  --query $QUERY --output=text)
echo $POLICY_ARN

aws iam attach-role-policy \
  --region $AWS_REGION \
  --role-name $EMR_EKS_ROLE_NAME \
  --policy-arn $POLICY_ARN

# Update the trust policy of the job execution role

aws emr-containers update-role-trust-policy \
  --region $AWS_REGION \
  --cluster-name $EKS_CLUSTER \
  --namespace $EMR_K8s_NAMESPACE \
  --role-name $EMR_EKS_ROLE_NAME

# Register the Amazon EKS cluster with Amazon EMR

aws emr-containers create-virtual-cluster \
  --region $AWS_REGION \
  --name $EMR_VIRTUAL_CLUSTER \
  --container-provider "{
    \"id\": \"$EKS_CLUSTER\",
    \"type\": \"EKS\",
    \"info\": {
        \"eksInfo\": {
            \"namespace\": \"$EMR_K8s_NAMESPACE\"
        }
    }}"

QUERY=virtualClusters[?name==\`$EMR_VIRTUAL_CLUSTER\`].id
EMR_VIRTUAL_CLUSTER_ID=$(aws emr-containers list-virtual-clusters \
  --region $AWS_REGION \
  --states RUNNING \
  --query $QUERY --output=text | awk '{print $1;}')
echo $EMR_VIRTUAL_CLUSTER_ID

# Run a Python job

aws s3 cp s3://aws-data-analytics-workshops/emr-eks-workshop/scripts/pi.py .
aws s3 cp pi.py s3://$S3_BUCKET/scripts/

EMR_EKS_PYTHON_JOB_NAME=python-pi-$RANDOM

aws emr-containers start-job-run \
  --region $AWS_REGION \
  --virtual-cluster-id $EMR_VIRTUAL_CLUSTER_ID \
  --name $EMR_EKS_PYTHON_JOB_NAME \
  --execution-role-arn $EMR_EKS_ROLE_ARN \
  --release-label emr-6.2.0-latest \
  --job-driver "{
    \"sparkSubmitJobDriver\": {
        \"entryPoint\": \"s3://$S3_BUCKET/scripts/pi.py\",
        \"sparkSubmitParameters\": \"--conf spark.executor.instances=2 --conf spark.executor.memory=2G --conf spark.executor.cores=2 --conf spark.driver.cores=1\"
    }}" \
    --configuration-overrides "{
        \"monitoringConfiguration\": {
            \"cloudWatchMonitoringConfiguration\": {
                \"logGroupName\": \"$EKS_CLUSTER\",
                \"logStreamNamePrefix\": \"$EMR_EKS_PYTHON_JOB_NAME\"
            },
            \"s3MonitoringConfiguration\": {
                \"logUri\": \"s3://$S3_BUCKET/logs/eks\"
            }}}"

QUERY=jobRuns[?name==\`$EMR_EKS_PYTHON_JOB_NAME\`]
aws emr-containers list-job-runs \
  --region $AWS_REGION \
  --virtual-cluster-id $EMR_VIRTUAL_CLUSTER_ID \
  --query $QUERY

kubectl get pods --namespace $EMR_K8s_NAMESPACE -o wide

# Run a SQL Spark job

aws s3 cp  \
  --region $AWS_REGION \
  s3://amazon-reviews-pds/parquet/product_category=Toys/ \
  s3://$S3_BUCKET/input/toy \
  --recursive

cp amazonreview-TEMPLATE.sql amazonreview.sql
sed -i "" "s|EXAMPLE-BUCKET|$S3_BUCKET|g" amazonreview.sql
aws s3 cp \
  --region $AWS_REGION \
  amazonreview.sql \
  s3://$S3_BUCKET/scripts/amazonreview.sql

EMR_EKS_SPARK_SQL_JOB_NAME=spark-sql-toy-$RANDOM

aws emr-containers start-job-run \
  --region $AWS_REGION \
  --virtual-cluster-id $EMR_VIRTUAL_CLUSTER_ID \
  --name $EMR_EKS_SPARK_SQL_JOB_NAME \
  --execution-role-arn $EMR_EKS_ROLE_ARN \
  --release-label $EMR_VERSION-latest \
  --job-driver "{
    \"sparkSqlJobDriver\": {
        \"entryPoint\": \"s3://$S3_BUCKET/scripts/amazonreview.sql\",
        \"sparkSqlParameters\": \"--conf spark.executor.instances=2 --conf spark.executor.memory=2G --conf spark.executor.cores=2 --conf spark.driver.cores=1\"
    }}" \
  --configuration-overrides "{
    \"monitoringConfiguration\": {
        \"cloudWatchMonitoringConfiguration\": {
                \"logGroupName\": \"$EKS_CLUSTER\",
                \"logStreamNamePrefix\": \"$EMR_EKS_SPARK_SQL_JOB_NAME\"
        },
        \"s3MonitoringConfiguration\": {
            \"logUri\": \"s3://$S3_BUCKET/logs/eks\"
        }}}"

QUERY=jobRuns[?name==\`$EMR_EKS_SPARK_SQL_JOB_NAME\`]
aws emr-containers list-job-runs \
  --region $AWS_REGION \
  --virtual-cluster-id $EMR_VIRTUAL_CLUSTER_ID \
  --query $QUERY

kubectl get pods --namespace $EMR_K8s_NAMESPACE -o wide
# NAME                        READY   STATUS        RESTARTS   AGE     IP               NODE                                     NOMINATED NODE   READINESS GATES
# 000000031bobftf6de9-ssthx   2/3     Terminating   0          2m38s   192.168.109.10   fargate-ip-192-168-109-10.ec2.internal   <none>           <none>


# Run a PySpark job (DOES NOT WORK)

EMR_EKS_PYSPARK_JOB_NAME=spark-python-wordcount-$RANDOM

aws emr-containers start-job-run \
  --region $AWS_REGION \
  --virtual-cluster-id $EMR_VIRTUAL_CLUSTER_ID \
  --name $EMR_EKS_PYSPARK_JOB_NAME \
  --execution-role-arn $EMR_EKS_ROLE_ARN \
  --release-label emr-6.9.0-latest \
  --job-driver "{
    \"sparkSubmitJobDriver\": {
        \"entryPoint\": \"s3://$S3_BUCKET/scripts/wordcount.py\",
        \"entryPointArguments\": [\"s3://$S3_BUCKET/output/eks\"],
        \"sparkSubmitParameters\": \"--conf spark.executor.instances=2 --conf spark.executor.memory=2G --conf spark.executor.cores=2 --conf spark.driver.cores=1\"
    }}" \
    --configuration-overrides "{
        \"monitoringConfiguration\": {
            \"cloudWatchMonitoringConfiguration\": {
                \"logGroupName\": \"$EKS_CLUSTER\",
                \"logStreamNamePrefix\": \"$EMR_EKS_PYSPARK_JOB_NAME\"
            },
            \"s3MonitoringConfiguration\": {
                \"logUri\": \"s3://$S3_BUCKET/logs/eks\"
            }}}"

QUERY=jobRuns[?name==\`$EMR_EKS_PYSPARK_JOB_NAME\`]
aws emr-containers list-job-runs \
  --region $AWS_REGION \
  --virtual-cluster-id $EMR_VIRTUAL_CLUSTER_ID \
  --query $QUERY

kubectl get pods --namespace $EMR_K8s_NAMESPACE -o wide
#NAME                               READY   STATUS              RESTARTS   AGE    IP                NODE                                      NOMINATED NODE   READINESS GATES
#000000031bpm6g8eonb-whpn2          3/3     Running             0          3m4s   192.168.124.163   fargate-ip-192-168-124-163.ec2.internal   <none>           <none>
#spark-000000031bpm6g8eonb-driver   0/2     ContainerCreating   0          77s    <none>            fargate-ip-192-168-72-63.ec2.internal     <none>           <none>


# Run a PySpark job (DOES NOT WORK)

aws s3 cp s3://aws-data-analytics-workshops/emr-eks-workshop/scripts/spark-etl.py nyctaxi.py
aws s3 cp nyctaxi.py s3://$S3_BUCKET/scripts/

aws s3 cp  \
  --region $AWS_REGION \
  s3://aws-data-analytics-workshops/shared_datasets/tripdata/ \
  s3://$S3_BUCKET/input/nyctaxi \
  --recursive
  
EMR_EKS_PYSPARK2_JOB_NAME=spark-python-nyctaxi-$RANDOM

aws emr-containers start-job-run \
  --region $AWS_REGION \
  --virtual-cluster-id $EMR_VIRTUAL_CLUSTER_ID \
  --name $EMR_EKS_PYSPARK2_JOB_NAME \
  --execution-role-arn $EMR_EKS_ROLE_ARN \
  --release-label emr-6.9.0-latest \
  --job-driver "{
    \"sparkSubmitJobDriver\": {
        \"entryPoint\": \"s3://$S3_BUCKET/scripts/nyctaxi.py\",
        \"entryPointArguments\": [
          \"s3://$S3_BUCKET/input/nyctaxi/\",
          \"s3://$S3_BUCKET/logs/eks/\"],
        \"sparkSubmitParameters\": \"--conf spark.executor.instances=2 --conf spark.executor.memory=2G --conf spark.executor.cores=2 --conf spark.driver.cores=1\"
    }}" \
    --configuration-overrides "{
        \"monitoringConfiguration\": {
            \"cloudWatchMonitoringConfiguration\": {
                \"logGroupName\": \"$EKS_CLUSTER\",
                \"logStreamNamePrefix\": \"$EMR_EKS_PYSPARK2_JOB_NAME\"
            },
            \"s3MonitoringConfiguration\": {
                \"logUri\": \"s3://$S3_BUCKET/logs/eks\"
            }}}"

QUERY=jobRuns[?name==\`$EMR_EKS_PYSPARK2_JOB_NAME\`]
aws emr-containers list-job-runs \
  --region $AWS_REGION \
  --virtual-cluster-id $EMR_VIRTUAL_CLUSTER_ID \
  --query $QUERY

kubectl get pods --namespace $EMR_K8s_NAMESPACE -o wide