These bash scripts are used to demo the setup of Amazon EMR environments and the launch of simple data batch examples. These commands and jobs are mainly based on the AWS documentation.

The following environments are included:
- [**Amazon EMR on EC2**](https://docs.aws.amazon.com/emr/latest/ManagementGuide/emr-what-is-emr.html): [emr-ec2-create.sh](/emr-ec2-create.sh), [emr-ec2-delete.sh](/emr-ec2-delete.sh)
- [**Amazon EMR on EKS / Fargate**](https://docs.aws.amazon.com/emr/latest/EMR-on-EKS-DevelopmentGuide/emr-eks.html): [emr-eks-create.sh](/emr-eks-create.sh), [emr-eks-delete.sh](/emr-eks-delete.sh)
- [**Amazon EMR Serverless**](https://docs.aws.amazon.com/emr/latest/EMR-Serverless-UserGuide/emr-serverless.html): [emr-serverless-create.sh](/emr-serverless-create.sh), [emr-serverless-delete.sh](/emr-serverless-delete.sh)

![overview](https://d1.awsstatic.com/products/EMR/Product-Page-Diagram_Amazon-EMR.803d6adad956ba21ceb96311d15e5022c2b6722b.png)
