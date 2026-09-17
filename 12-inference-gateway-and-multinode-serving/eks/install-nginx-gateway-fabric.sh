#!/usr/bin/env bash
# Install NGINX Gateway Fabric with the Gateway API Inference Extension feature turned on.
# Pin NGF_VERSION here (not in versions.env -- other agents write it concurrently; report it
# in the README "Versions tested" section instead). 2.7.0 is the latest stable NGF release
# verified via web search at pin time; confirm against
# https://github.com/nginx/nginx-gateway-fabric/releases before class time.
#   ./install-nginx-gateway-fabric.sh
set -euo pipefail
NGF_VERSION="${NGF_VERSION:-2.7.0}" # VERIFY

helm upgrade --install ngf oci://ghcr.io/nginx/charts/nginx-gateway-fabric \
  --version "$NGF_VERSION" \
  --namespace nginx-gateway --create-namespace \
  --set nginxGateway.gwAPIInferenceExtension.enable=true \
  --wait --timeout 5m

kubectl get gatewayclass nginx
echo "NGINX Gateway Fabric ${NGF_VERSION} installed (GatewayClass: nginx)."
