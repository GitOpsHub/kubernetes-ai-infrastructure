#!/usr/bin/env bash
# ALTERNATIVE to kube-prometheus-stack: Amazon Managed Service for Prometheus (AMP), scraped by
# an AWS-managed collector (no ADOT DaemonSet/Deployment to run or upgrade yourself). Trade-off:
# no bundled Alertmanager/Grafana (pair with Amazon Managed Grafana or your own), and the managed
# collector needs ENIs in your VPC subnets (extra IPs/cost) - read the pricing page before fleet use.
# CREATES BILLED AWS RESOURCES. Not run by this course; read it, then run it yourself if you want
# the managed path instead of (or alongside) kube-prometheus-stack.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
[[ -f "$ROOT/env.sh" ]] && source "$ROOT/env.sh"
: "${AWS_REGION:?}" "${EKS_CLUSTER:?}"
WORKSPACE_ALIAS="${WORKSPACE_ALIAS:-ch04-gpu-observability}"

WORKSPACE_ID=$(aws amp create-workspace --alias "$WORKSPACE_ALIAS" --region "$AWS_REGION" \
  --query workspaceId --output text)
echo "AMP workspace: $WORKSPACE_ID"

# Minimal scrape config: same target as common/servicemonitor, translated to a plain Prometheus
# scrape_config (the managed collector doesn't consume ServiceMonitor CRs, it consumes this).
cat > /tmp/amp-scrape-config.yaml <<'EOF'
global:
  scrape_interval: 30s
scrape_configs:
  - job_name: dcgm-exporter
    kubernetes_sd_configs:
      - role: pod
        namespaces: { names: ["gpu-operator"] }
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_label_app]
        regex: nvidia-dcgm-exporter
        action: keep
      - source_labels: [__meta_kubernetes_pod_container_port_name]
        regex: gpu-metrics
        action: keep
EOF
SCRAPE_CONFIG_B64=$(base64 < /tmp/amp-scrape-config.yaml | tr -d '\n')

# VERIFY: --source-eks requires clusterArn + subnetIds (private subnets with connectivity to the
# EKS API endpoint and to the pod network) and securityGroupIds; get exact current syntax with
# `aws amp create-scraper help` before running - this API is newer than this course's training
# data cutoff and flags may have changed.
aws amp create-scraper \
  --region "$AWS_REGION" \
  --scrape-configuration "configurationBlob=${SCRAPE_CONFIG_B64}" \
  --destination "ampConfiguration={workspaceArn=arn:aws:aps:${AWS_REGION}:$(aws sts get-caller-identity --query Account --output text):workspace/${WORKSPACE_ID}}" \
  --alias "ch04-dcgm-scraper"
# See: https://docs.aws.amazon.com/prometheus/latest/userguide/AMP-collector-how-to.html
