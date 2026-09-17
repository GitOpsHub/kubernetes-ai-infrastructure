#!/usr/bin/env bash
# Read-only health check across every layer of the platform — the capstone's "is it actually
# wired together" checklist, runnable at any point during/after deploy-platform.sh. Nothing here
# mutates the cluster.
set -euo pipefail
echo "== Kueue: quota + admission (ch06, ch16 bridge) =="
kubectl get resourceflavor,clusterqueue,cohort 2>&1
kubectl get localqueue -A 2>&1

echo "== GPU nodes + device plugin (ch01-02) =="
kubectl get nodes -L nvidia.com/gpu.present,kubernetes.azure.com/scalesetpriority 2>&1
kubectl -n gpu-operator get pods 2>&1 || true

echo "== Observability (ch04) =="
kubectl -n monitoring get pods -l app.kubernetes.io/name=prometheus 2>&1 || true

echo "== Training / serving frameworks (ch07-09, 11) =="
kubectl -n ch07-training get trainjobs,trainingruntimes 2>&1 || true
kubectl -n ch09-vllm get deployments,pods 2>&1 || true
kubectl -n kserve get pods 2>&1 || true

echo "== Gateway + multi-node + autoscaling (ch10, 12-13) =="
kubectl -n ch12-gateway get gateway,httproute,inferencepool 2>&1 || true
kubectl -n ch09-vllm get scaledobject,hpa 2>&1 || true

echo "== Security (ch14) =="
kubectl get validatingadmissionpolicy,clusterpolicy 2>&1 || true
kubectl -n ch14-team-a get resourcequota,networkpolicy 2>&1 || true
kubectl -n external-secrets get pods 2>&1 || true

echo "== GitOps + pipelines + registry (ch15-16) =="
kubectl get application -n argocd -l app.kubernetes.io/part-of=ai-platform 2>&1 || true
kubectl -n ch15-pipelines get workflowtemplates,workflows 2>&1 || true
kubectl -n mlflow get pods 2>&1 || true

echo "Review each section above for CrashLoopBackOff/Pending/0-ready before calling the platform healthy."
