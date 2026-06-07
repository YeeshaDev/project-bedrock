# Runbook & Troubleshooting Guide — Project Bedrock

## Quick Reference

| Item | Value |
|---|---|
| AWS Region | us-east-1 |
| EKS Cluster | project-bedrock-cluster |
| App Namespace | retail-app |
| Terraform State Bucket | (check `terraform/backend.tf`) |
| Assets S3 Bucket | bedrock-assets-alt-soe-025-4808 |
| DynamoDB Table | project-bedrock-carts |
| GitHub Repo | https://github.com/YeeshaDev/project-bedrock |

---

## Part 1 — Runbook (Bringing Everything Back Up)

### Prerequisites

Ensure you have these installed locally:
```bash
aws --version          # AWS CLI v2
terraform --version    # ~1.9
kubectl version        # 1.30+
helm version           # 3.x
```

Ensure AWS credentials are configured:
```bash
aws sts get-caller-identity
```

---

### Step 1 — Bootstrap Terraform Remote State (first time only)

If the S3 backend bucket does not exist yet:
```bash
cd terraform/backend-bootstrap
terraform init
terraform apply -auto-approve
```

---

### Step 2 — Initialise Terraform

```bash
cd terraform
terraform init
```

---

### Step 3 — Import Existing SG Rules (if cluster already exists)

If the EKS cluster exists but the SG rules were created manually and are not yet in state:

```bash
CLUSTER_SG=$(aws eks describe-cluster \
  --name project-bedrock-cluster \
  --region us-east-1 \
  --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' \
  --output text)

echo "Cluster SG: $CLUSTER_SG"

# Import HTTP rule (port 80)
terraform state show module.eks.aws_security_group_rule.cluster_http_ingress \
  > /dev/null 2>&1 || \
  terraform import \
    module.eks.aws_security_group_rule.cluster_http_ingress \
    "${CLUSTER_SG}_ingress_tcp_80_80_0.0.0.0/0"

# Import HTTPS rule (port 443)
terraform state show module.eks.aws_security_group_rule.cluster_https_ingress \
  > /dev/null 2>&1 || \
  terraform import \
    module.eks.aws_security_group_rule.cluster_https_ingress \
    "${CLUSTER_SG}_ingress_tcp_443_443_0.0.0.0/0"
```

---

### Step 4 — Apply Infrastructure

```bash
cd terraform
export TF_VAR_db_password_catalog="<secret>"
export TF_VAR_db_password_orders="<secret>"
terraform apply -auto-approve
```

---

### Step 5 — Configure kubectl

```bash
aws eks update-kubeconfig --name project-bedrock-cluster --region us-east-1
kubectl get nodes  # wait until all nodes are Ready
```

---

### Step 6 — Install AWS Load Balancer Controller

```bash
LBC_ROLE_ARN=$(cd terraform && terraform output -raw lbc_role_arn)
VPC_ID=$(cd terraform && terraform output -raw vpc_id)

helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName=project-bedrock-cluster \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=${LBC_ROLE_ARN}" \
  --set region=us-east-1 \
  --set vpcId=${VPC_ID} \
  --wait --timeout 10m

kubectl rollout restart deployment/aws-load-balancer-controller -n kube-system
kubectl rollout status deployment/aws-load-balancer-controller -n kube-system --timeout=120s
```

---

### Step 7 — Deploy Kubernetes Namespace, RBAC, and App

```bash
kubectl apply -f kubernetes/namespace.yaml
kubectl apply -f kubernetes/rbac.yaml

# Create DB secrets from Secrets Manager
CATALOG_RAW=$(aws secretsmanager get-secret-value \
  --secret-id project-bedrock/catalog-db-credentials \
  --query SecretString --output text)
CATALOG_HOST=$(echo "$CATALOG_RAW" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['host']+':3306')")
CATALOG_USER=$(echo "$CATALOG_RAW" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['username'])")
CATALOG_PASS=$(echo "$CATALOG_RAW" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['password'])")

kubectl create secret generic catalog-db-secret \
  --namespace retail-app \
  --from-literal=endpoint="$CATALOG_HOST" \
  --from-literal=username="$CATALOG_USER" \
  --from-literal=password="$CATALOG_PASS" \
  --dry-run=client -o yaml | kubectl apply -f -

ORDERS_RAW=$(aws secretsmanager get-secret-value \
  --secret-id project-bedrock/orders-db-credentials \
  --query SecretString --output text)
ORDERS_HOST=$(echo "$ORDERS_RAW" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['host']+':5432')")
ORDERS_USER=$(echo "$ORDERS_RAW" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['username'])")
ORDERS_PASS=$(echo "$ORDERS_RAW" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['password'])")

kubectl create secret generic orders-db-secret \
  --namespace retail-app \
  --from-literal=endpoint="$ORDERS_HOST" \
  --from-literal=username="$ORDERS_USER" \
  --from-literal=password="$ORDERS_PASS" \
  --dry-run=client -o yaml | kubectl apply -f -

# Deploy app
kubectl apply -k kubernetes/retail-app/ --timeout=600s

# Annotate Carts for IRSA
CART_ROLE_ARN=$(cd terraform && terraform output -raw cart_irsa_role_arn)
kubectl annotate serviceaccount carts \
  --namespace retail-app \
  "eks.amazonaws.com/role-arn=${CART_ROLE_ARN}" \
  --overwrite
kubectl rollout restart deployment/carts -n retail-app

# Apply HTTP ingress
kubectl apply -f kubernetes/ingress.yaml
```

---

### Step 8 — Install NGINX Ingress Controller

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer \
  --set 'controller.service.annotations.service\.beta\.kubernetes\.io/aws-load-balancer-type=external' \
  --set 'controller.service.annotations.service\.beta\.kubernetes\.io/aws-load-balancer-nlb-target-type=ip' \
  --set 'controller.service.annotations.service\.beta\.kubernetes\.io/aws-load-balancer-scheme=internet-facing' \
  --wait --timeout 5m
```

---

### Step 9 — Install cert-manager

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update

helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true \
  --wait --timeout 5m

kubectl apply -f kubernetes/cert-manager/cluster-issuer.yaml
```

---

### Step 10 — Deploy TLS Ingress (nip.io)

```bash
# Wait for NLB hostname
NLB_HOSTNAME=""
for i in $(seq 1 20); do
  NLB_HOSTNAME=$(kubectl get svc ingress-nginx-controller -n ingress-nginx \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
  [ -n "$NLB_HOSTNAME" ] && break
  echo "  attempt $i/20 — waiting 15s"
  sleep 15
done
echo "NLB hostname: $NLB_HOSTNAME"

# Resolve to IP
NIP_IP=$(dig +short "$NLB_HOSTNAME" A | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
echo "IP: $NIP_IP"

export NIP_IO_DOMAIN="${NIP_IP}.nip.io"
echo "App URL: https://${NIP_IO_DOMAIN}"

envsubst < kubernetes/ingress-tls.yaml | kubectl apply -f -
```

---

### Step 11 — Configure CoreDNS Split DNS

```bash
NGINX_CLUSTER_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx \
  -o jsonpath='{.spec.clusterIP}')

kubectl get configmap coredns -n kube-system \
  -o jsonpath='{.data.Corefile}' > /tmp/corefile.txt

python3 scripts/patch_coredns.py "$NGINX_CLUSTER_IP" "$NIP_IO_DOMAIN"

kubectl create configmap coredns \
  --from-file=Corefile=/tmp/corefile_new.txt \
  -n kube-system --dry-run=client -o yaml | kubectl apply -f -

kubectl rollout restart deployment/coredns -n kube-system
kubectl rollout status deployment/coredns -n kube-system --timeout=90s
```

---

### Step 12 — Verify Everything is Running

```bash
kubectl get nodes
kubectl get pods -n retail-app
kubectl get pods -n ingress-nginx
kubectl get pods -n cert-manager
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
kubectl get ingress -n retail-app
kubectl get certificate -n retail-app
```

Expected: all pods Running, certificate Ready=True.

---

### Step 13 — Generate grading.json

```bash
cd terraform
terraform output -json | jq 'with_entries(select(.value.sensitive == false))' > ../grading.json
git add ../grading.json
git commit -m "chore: update grading.json"
git push origin main
```

---

## Part 2 — Troubleshooting

---

### T1 — Terraform Import Fails for SG Rules

**Symptom:**
```
Error: unexpected format for ID, expected SECURITYGROUPID_TYPE_PROTOCOL_FROMPORT_TOPORT_SOURCE
```

**Cause:** Using the `sgr-*` ID format. The AWS provider requires the compound key format.

**Fix:** Use the compound format:
```bash
CLUSTER_SG=$(aws eks describe-cluster \
  --name project-bedrock-cluster --region us-east-1 \
  --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' --output text)

terraform import module.eks.aws_security_group_rule.cluster_http_ingress \
  "${CLUSTER_SG}_ingress_tcp_80_80_0.0.0.0/0"

terraform import module.eks.aws_security_group_rule.cluster_https_ingress \
  "${CLUSTER_SG}_ingress_tcp_443_443_0.0.0.0/0"
```

---

### T2 — Terraform Import Prompts Interactively for Variables

**Symptom:**
```
var.db_password_catalog
  Enter a value:
```

**Cause:** `TF_VAR_*` env vars are not set before running `terraform import`.

**Fix:**
```bash
export TF_VAR_db_password_catalog="<value>"
export TF_VAR_db_password_orders="<value>"
terraform import ...
```

---

### T3 — NLB Hostname Not Available After NGINX Install

**Symptom:** Loop times out waiting for `ingress-nginx-controller` service hostname.

**Diagnosis:**
```bash
kubectl get svc ingress-nginx-controller -n ingress-nginx
kubectl describe svc ingress-nginx-controller -n ingress-nginx
kubectl get pods -n ingress-nginx
```

**Fix:** Check that the AWS Load Balancer Controller is healthy first:
```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=50
```
If LBC pods are crashing, restart them:
```bash
kubectl rollout restart deployment/aws-load-balancer-controller -n kube-system
```

---

### T4 — nip.io URL Not Opening (Connection Timeout)

**Symptom:** `https://<IP>.nip.io` times out in browser.

**Diagnosis checklist:**
```bash
# 1. Is NGINX pod running?
kubectl get pods -n ingress-nginx

# 2. Does the NLB have healthy targets?
# Get NLB ARN from AWS console or:
aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?contains(DNSName, 'k8s-ingressn')].LoadBalancerArn" \
  --output text

# 3. Check cluster SG has port 80/443 open
CLUSTER_SG=$(aws eks describe-cluster \
  --name project-bedrock-cluster --region us-east-1 \
  --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' --output text)
aws ec2 describe-security-group-rules \
  --filters "Name=group-id,Values=$CLUSTER_SG" \
  --query "SecurityGroupRules[?IsEgress==\`false\`].[FromPort,ToPort,CidrIpv4]" \
  --output table
```

**Fix:** If port 80/443 rules are missing:
```bash
aws ec2 authorize-security-group-ingress \
  --group-id "$CLUSTER_SG" --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress \
  --group-id "$CLUSTER_SG" --protocol tcp --port 443 --cidr 0.0.0.0/0
```
Then re-run terraform import + apply so Terraform manages them.

---

### T5 — TLS Certificate Not Issuing

**Symptom:** `https://` shows SSL error or cert is for wrong domain.

**Diagnosis:**
```bash
kubectl get certificate -n retail-app
kubectl describe certificate retail-store-tls -n retail-app
kubectl get orders.acme.cert-manager.io -n retail-app
kubectl get challenges.acme.cert-manager.io -n retail-app
kubectl describe challenge -n retail-app
```

**Common cause:** HTTP-01 challenge cannot reach the NLB (NLB targets not yet healthy when cert-manager fires).

**Fix — force reissuance after NLB is stable:**
```bash
kubectl delete certificate retail-store-tls -n retail-app
kubectl delete orders.acme.cert-manager.io,challenges.acme.cert-manager.io -n retail-app --all 2>/dev/null || true

# Re-apply TLS ingress to trigger cert-manager
export NIP_IO_DOMAIN="<IP>.nip.io"
envsubst < kubernetes/ingress-tls.yaml | kubectl apply -f -

# Watch cert status
kubectl get certificate retail-store-tls -n retail-app -w
```

---

### T6 — App Pods Not Starting (CrashLoopBackOff / Pending)

**Diagnosis:**
```bash
kubectl get pods -n retail-app
kubectl describe pod <pod-name> -n retail-app
kubectl logs <pod-name> -n retail-app --previous
```

**Common causes:**

| Symptom | Cause | Fix |
|---|---|---|
| `Pending` | No nodes available or resource limits | `kubectl describe node` — check capacity |
| `CreateContainerConfigError` | Secret missing | Re-run Step 7 (DB secrets) |
| DB connection refused | Wrong endpoint in secret | Check secret values vs RDS endpoint |
| Carts pod crashes | IRSA role not annotated | Re-run IRSA annotation in Step 7 |

---

### T7 — AWS Load Balancer Controller Webhook Errors

**Symptom:** Ingress not reconciling; LBC logs show certificate/webhook errors.

**Fix:**
```bash
kubectl rollout restart deployment/aws-load-balancer-controller -n kube-system
kubectl rollout status deployment/aws-load-balancer-controller -n kube-system --timeout=120s
```

---

### T8 — CoreDNS Not Routing Internal nip.io Requests

**Symptom:** Services inside the cluster can't resolve the nip.io domain.

**Diagnosis:**
```bash
kubectl get configmap coredns -n kube-system -o jsonpath='{.data.Corefile}'
```

**Fix:** Re-run Step 11 (CoreDNS split DNS) with the current `NIP_IO_DOMAIN` and `NGINX_CLUSTER_IP`.

---

### T9 — GitHub Actions Pipeline Fails on OIDC Auth

**Symptom:**
```
Error: Could not assume role with OIDC
```

**Cause:** The IAM role trust policy references the old repo name, or the GitHub OIDC provider is not set up in the AWS account.

**Fix:** In AWS Console → IAM → Roles → `project-bedrock-cluster-github-actions-role` → Trust relationships. Ensure the condition matches:
```json
"repo:YeeshaDev/project-bedrock:ref:refs/heads/main"
```

---

### T10 — grading.json Contains Sensitive Keys

**Symptom:** Access keys visible in the public repo.

**Fix — regenerate without sensitive fields:**
```bash
cd terraform
terraform output -json | jq 'with_entries(select(.value.sensitive == false))' > ../grading.json
git add ../grading.json && git commit -m "chore: strip sensitive outputs from grading.json"
git push origin main
```
Then rotate the exposed keys immediately in AWS Console → IAM → `bedrock-dev-view` → Security credentials.

---

### T11 — Lambda Not Triggering on S3 Upload

**Diagnosis:**
```bash
# Check Lambda function exists
aws lambda get-function --function-name <function-name> --region us-east-1

# Check S3 event notification is configured
aws s3api get-bucket-notification-configuration --bucket bedrock-assets-alt-soe-025-4808

# Check Lambda logs
aws logs tail /aws/lambda/<function-name> --follow
```

**Fix:** If the S3 notification is missing, re-run `terraform apply` — the S3-Lambda trigger is managed by the `s3-lambda` Terraform module.

---

## Tear Down Order

To destroy cleanly without orphaned resources:

```bash
# 1. Remove Kubernetes resources first (so LBC can delete ALB/NLB cleanly)
kubectl delete -f kubernetes/ingress.yaml 2>/dev/null || true
kubectl delete -f kubernetes/ingress-tls.yaml 2>/dev/null || true
kubectl delete -k kubernetes/retail-app/ 2>/dev/null || true
helm uninstall ingress-nginx -n ingress-nginx 2>/dev/null || true
helm uninstall aws-load-balancer-controller -n kube-system 2>/dev/null || true
helm uninstall cert-manager -n cert-manager 2>/dev/null || true

# 2. Wait for NLB/ALB to be deleted by AWS (~60s)
sleep 60

# 3. Destroy Terraform
cd terraform
export TF_VAR_db_password_catalog="<value>"
export TF_VAR_db_password_orders="<value>"
terraform destroy -auto-approve
```

> **Warning:** `terraform destroy` will delete RDS databases, DynamoDB table, S3 bucket contents, and the EKS cluster. This is irreversible.
