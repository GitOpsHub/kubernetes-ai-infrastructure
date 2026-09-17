#!/usr/bin/env bash
# Install NGINX Gateway Fabric with the Gateway API Inference Extension feature turned on.
# NGF_VERSION pinned here, not versions.env -- report it in README "Versions tested".
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
