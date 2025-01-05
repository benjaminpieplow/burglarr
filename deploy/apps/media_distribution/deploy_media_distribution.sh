#!/bin/bash
# Author: Benjamin Rohner
# Date: 2024-12-23
# Description: Deploys Plex via Helm onto Kubernetes

# Path to kubeconfig
export KUBECONFIG=$HOME/.kube/config-bglr

# Add the helm repo to Kubernetes
helm repo add plex https://raw.githubusercontent.com/plexinc/pms-docker/gh-pages

# Apply the Plex configuration
helm upgrade --install plex plex/plex-media-server --values plex_values.yaml