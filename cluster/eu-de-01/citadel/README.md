kubectl exec -it deployment/citadel-webserver -n citadel -- tail -f /app/log/production.log

kubectl exec -it deployment/citadel-webserver -n citadel -- grep -f /app/log/production.log | grep --line-buffered "league_matches" | grep "121"

**Request ID**
kubectl exec deployment/citadel-webserver -n citadel -- grep "962d0556-8c0e-4f01-915e-09b0872f0b65" /app/log/production.log
