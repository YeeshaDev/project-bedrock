# Project Bedrock - InnovateMart EKS Deployment

Production-grade microservices infrastructure on AWS EKS for InnovateMart Inc.

---

## Architecture

- **VPC**: `project-bedrock-vpc` — 2 public + 2 private subnets across `us-east-1a` and `us-east-1b`
- **EKS**: `project-bedrock-cluster` (v1.34) with managed node group (`t3.medium`)
- **Data Layer**: RDS MySQL (catalog), RDS PostgreSQL (orders), DynamoDB (carts)
- **Ingress**: AWS Load Balancer Controller → ALB
- **Serverless**: S3 (`bedrock-assets-alt-soe-025-4808`) → Lambda (`bedrock-asset-processor`)
- **Observability**: EKS control plane logs + CloudWatch Observability addon
- **CI/CD**: GitHub Actions with OIDC (no long-lived keys)

---

## Prerequisites

- AWS CLI configured (`aws configure`) with an IAM user that has `AdministratorAccess`
- Terraform >= 1.5
- kubectl
- Helm >= 3
- A GitHub repository created (you'll need the `owner/repo-name` for the first apply)

**GitHub repository secrets to add after Step 1:**

| Secret | Value |
|--------|-------|
| `AWS_ROLE_ARN` | Output of `terraform output github_actions_role_arn` |
| `DB_PASSWORD_CATALOG` | The MySQL password you chose |
| `DB_PASSWORD_ORDERS` | The PostgreSQL password you chose |

---

## Step 0 — Bootstrap Remote State

Run once before anything else:

```bash
cd terraform/backend-bootstrap
terraform init
terraform apply
```

This creates the S3 bucket (`project-bedrock-tfstate-alt-soe-025-4808`) used as the Terraform backend.

---

## Step 1 — Deploy Infrastructure

```bash
cd terraform
terraform init
terraform apply \
  -var="db_password_catalog=YourCatalogPass1!" \
  -var="db_password_orders=YourOrdersPass1!" \
  -var="github_repo=your-github-username/your-repo-name"
```

This provisions: VPC → EKS → IAM → RDS → DynamoDB → S3/Lambda → CloudWatch.

> EKS takes ~15 minutes. RDS takes ~10 minutes.

After apply completes, run:

```bash
terraform output github_actions_role_arn
```

Copy that ARN and add it as the `AWS_ROLE_ARN` secret in your GitHub repository. From this point on, your local AWS credentials are only needed if you run Terraform manually — the pipeline uses OIDC.

---

## Step 2 — Configure kubectl

```bash
aws eks update-kubeconfig --name project-bedrock-cluster --region us-east-1
```

---

## Step 3 — Apply Kubernetes Manifests

```bash
kubectl apply -f kubernetes/namespace.yaml
kubectl apply -f kubernetes/rbac.yaml
```

---

## Step 4 — Deploy the Retail Store App

Get the RDS endpoints from Terraform outputs:

```bash
CATALOG_HOST=$(terraform -chdir=terraform output -raw catalog_rds_endpoint)
ORDERS_HOST=$(terraform -chdir=terraform output -raw orders_rds_endpoint)
```

Deploy via Helm:

```bash
helm repo add aws-retail-store https://aws-samples.github.io/retail-store-sample-app/helm
helm repo update

helm upgrade --install retail-store aws-retail-store/retail-store-sample-app \
  --namespace retail-app \
  --create-namespace \
  --values kubernetes/retail-app/values.yaml \
  --set catalog.mysql.external.host=$CATALOG_HOST \
  --set orders.postgresql.external.host=$ORDERS_HOST \
  --timeout 10m \
  --wait
```

---

## Step 5 — Apply Ingress

```bash
kubectl apply -f kubernetes/ingress.yaml
```

Retrieve the ALB URL:

```bash
kubectl get ingress -n retail-app retail-store-ingress
```

The `ADDRESS` column is the public URL for the Retail Store.

---

## Step 6 — Generate Grading Output

```bash
cd terraform
terraform output -json > ../grading.json
```

---

## CI/CD Pipeline

| Event | Action |
|-------|--------|
| Pull Request to `main` | `terraform plan` → output posted as PR comment |
| Merge to `main` | `terraform apply` → K8s manifests applied → Helm deploy |

The pipeline uses GitHub OIDC to assume the `project-bedrock-cluster-github-actions-role` — no static AWS keys stored in secrets.

**First-time setup**: After `terraform apply`, copy the `github_actions_role_arn` output and add it as the `AWS_ROLE_ARN` secret in your GitHub repository.

---

## Developer Access — `bedrock-dev-view`

Retrieve credentials after apply:

```bash
terraform -chdir=terraform output -raw dev_user_access_key_id
terraform -chdir=terraform output -raw dev_user_secret_key
terraform -chdir=terraform output -raw dev_user_password
```

This user can:
- ✅ `kubectl get pods -n retail-app`
- ❌ `kubectl delete pod` (permission denied)
- ✅ `aws s3 cp <file> s3://bedrock-assets-alt-soe-025-4808/`

---

## Serverless — Asset Processor

Upload a test file to trigger the Lambda:

```bash
aws s3 cp ./test-image.jpg s3://bedrock-assets-alt-soe-025-4808/ \
  --profile bedrock-dev-view
```

Check CloudWatch Logs → `/aws/lambda/bedrock-asset-processor` for:
```
Image received: test-image.jpg
```

---

## Cost Control

Pause when not working:

```bash
# Scale down node group to 0
aws eks update-nodegroup-config \
  --cluster-name project-bedrock-cluster \
  --nodegroup-name project-bedrock-cluster-nodes \
  --scaling-config minSize=0,maxSize=3,desiredSize=0

# Stop RDS instances
aws rds stop-db-instance --db-instance-identifier project-bedrock-catalog
aws rds stop-db-instance --db-instance-identifier project-bedrock-orders
```

---

## Tags

All resources are tagged: `Project: karatu-2025-capstone`
