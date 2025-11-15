
helm repo add k8s-at-home https://k8s-at-home.com/charts/
helm repo update
helm show values k8s-at-home/sonarr >> sonarr-values.yaml

# Configure the values