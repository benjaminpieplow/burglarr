## BIG WARNING
exit
## DO NOT RUN!
## I thought I'd do this with Helm, turns out, those charts are not maintained and _far_ too basic for my deployment. Manifests it is!


helm repo add k8s-at-home https://k8s-at-home.com/charts/
helm repo update
helm install -f deploy/apps/sonarr/sonarr-values.yaml sonarr k8s-at-home/sonarr
