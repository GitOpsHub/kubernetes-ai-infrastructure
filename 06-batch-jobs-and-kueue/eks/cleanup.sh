#!/usr/bin/env bash
set -euo pipefail
: "${EKS_CLUSTER:?source env.sh}" "${AWS_REGION:?}"

kubectl delete -k 06-batch-jobs-and-kueue/eks --ignore-not-found
kubectl delete -f 06-batch-jobs-and-kueue/common/jobs --ignore-not-found
helm uninstall kueue -n kueue-system || true
kubectl delete namespace kueue-system --ignore-not-found

eksctl delete nodegroup --cluster "${EKS_CLUSTER}" --region "${AWS_REGION}" --name ch06-cpu-spot || true
eksctl delete nodegroup --cluster "${EKS_CLUSTER}" --region "${AWS_REGION}" --name ch06-cpu-ondemand || true
