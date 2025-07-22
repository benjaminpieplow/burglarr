# Error checking? No need - if there are errors, you will find them soon :)
kubectl apply -f ./deploy/infra/
kubectl apply -f ./deploy/apps/sonarr/
kubectl apply -f ./deploy/apps/radarr/
kubectl apply -f ./deploy/apps/lidarr/
kubectl apply -f ./deploy/apps/prowlarr/
kubectl apply -f ./deploy/apps/deluge/
kubectl apply -f ./deploy/apps/jellyfin/
kubectl apply -f ./deploy/apps/nginx/
kubectl apply -f ./deploy/apps/ombi/