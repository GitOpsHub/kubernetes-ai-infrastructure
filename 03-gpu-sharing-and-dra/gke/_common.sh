# shellcheck shell=bash disable=SC2034
# Sourced by the gke/*.sh scripts. Requires: source env.sh && source versions.env (repo root).
: "${PROJECT_ID:?source env.sh first}"
: "${GKE_CLUSTER:?source env.sh first}"
: "${REGION:?source env.sh first}"
: "${ZONE:?source env.sh first}"
# Location of the *cluster* (regional cluster -> REGION, zonal cluster -> ZONE).
# Chapter 00 creates a regional cluster; override with GKE_LOCATION=<zone> for zonal clusters.
LOCATION="${GKE_LOCATION:-$REGION}"
# GPUs only exist in some zones; pin the node pool to one that has L4 / A100 capacity.
NODE_ZONE="${GPU_ZONE:-$ZONE}"
