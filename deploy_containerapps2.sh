#!/bin/bash
set -e

# -----------------------------
# Load .env
# -----------------------------
if [ ! -f .env ]; then
  echo ".env not found!"
  exit 1
fi
export $(grep -v '^#' .env | xargs)

# -----------------------------
# Azure settings
# -----------------------------
RG="tomatom-rg"
ACR="tomatomacr7080"
ENV_NAME="tomatom-env"
BACKEND="tomatom-backend"
FRONTEND="tomatom-frontend"

# -----------------------------
# Login
# -----------------------------
echo "Logging in to Azure..."
az account show >/dev/null 2>&1 || az login
echo "Logging in to ACR..."
az acr login --name $ACR

# -----------------------------
# Build & push Docker images
# -----------------------------
echo "Building backend..."
docker build -t $ACR.azurecr.io/$BACKEND:latest ./backend
docker push $ACR.azurecr.io/$BACKEND:latest

echo "Building frontend..."
docker build -t $ACR.azurecr.io/$FRONTEND:latest ./frontend
docker push $ACR.azurecr.io/$FRONTEND:latest

# -----------------------------
# Create / update backend secrets
# -----------------------------
echo "Creating / updating backend secrets..."
az containerapp secret set \
  --name $BACKEND \
  --resource-group $RG \
  --secrets \
      storage="$AZURE_STORAGE_CONNECTION_STRING" \
      eventhubconnection="$EVENTHUB_CONNECTION_STRING"

# -----------------------------
# Deploy / Update backend
# -----------------------------
if ! az containerapp show -n $BACKEND -g $RG >/dev/null 2>&1; then
  echo "Creating backend..."
  az containerapp create \
    --name $BACKEND \
    --resource-group $RG \
    --environment $ENV_NAME \
    --image $ACR.azurecr.io/$BACKEND:latest \
    --target-port 8080 \
    --ingress external \
    --min-replicas 1 \
    --max-replicas 3 \
    --env-vars PORT=$PORT NODE_ENV=$NODE_ENV
else
  echo "Updating backend image..."
  az containerapp update \
    --name $BACKEND \
    --resource-group $RG \
    --image $ACR.azurecr.io/$BACKEND:latest \
    --set-env-vars PORT=$PORT NODE_ENV=$NODE_ENV
fi

# Attach secrets and other env vars
echo "Attaching secrets and env vars to backend..."
az containerapp update \
  --name $BACKEND \
  --resource-group $RG \
  --set-env-vars \
      AZURE_STORAGE_CONNECTION_STRING="@storage" \
      EVENTHUB_CONNECTION_STRING="@eventhubconnection" \
      EVENTHUB_NAMESPACE="$EVENTHUB_NAMESPACE" \
      RAW_CONTAINER_NAME="$RAW_CONTAINER_NAME" \
      PROCESSED_CONTAINER_NAME="$PROCESSED_CONTAINER_NAME" \
      EVENTHUB_NAME_UPLOADS="$EVENTHUB_NAME_UPLOADS" \
      KAFKA_TOPIC="$KAFKA_TOPIC" \
      PORT="$PORT" \
      NODE_ENV="$NODE_ENV"

# -----------------------------
# Deploy / Update frontend
# -----------------------------
BACKEND_FQDN=$(az containerapp show -n $BACKEND -g $RG --query properties.configuration.ingress.fqdn -o tsv)

if ! az containerapp show -n $FRONTEND -g $RG >/dev/null 2>&1; then
  echo "Creating frontend..."
  az containerapp create \
    --name $FRONTEND \
    --resource-group $RG \
    --environment $ENV_NAME \
    --image $ACR.azurecr.io/$FRONTEND:latest \
    --target-port 80 \
    --ingress external \
    --min-replicas 1 \
    --max-replicas 3 \
    --env-vars BACKEND_URL="https://$BACKEND_FQDN"
else
  echo "Updating frontend image..."
  az containerapp update \
    --name $FRONTEND \
    --resource-group $RG \
    --image $ACR.azurecr.io/$FRONTEND:latest \
    --set-env-vars BACKEND_URL="https://$BACKEND_FQDN"
fi

# -----------------------------
# Show URLs
# -----------------------------
BE_URL=$(az containerapp show -n $BACKEND -g $RG --query properties.configuration.ingress.fqdn -o tsv)
FE_URL=$(az containerapp show -n $FRONTEND -g $RG --query properties.configuration.ingress.fqdn -o tsv)
echo "Backend URL: https://$BE_URL"
echo "Frontend URL: https://$FE_URL"

# -----------------------------
# Check backend environment variables
# -----------------------------
echo "Checking backend environment variables..."
az containerapp show \
  --name $BACKEND \
  --resource-group $RG \
  --query properties.configuration.environmentVariables

# -----------------------------
# Wait for backend readiness
# -----------------------------
#echo "Checking backend readiness..."
#for i in {1..12}; do
#    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" https://$BE_URL/health || echo "000")
#    if [ "$HTTP_CODE" == "200" ]; then
#        echo "Backend is UP ✅"
#        break
#    else
#        echo "Backend not ready yet (HTTP $HTTP_CODE), waiting 5s..."
#        sleep 5
#    fi
#done
#
## -----------------------------
## Check frontend
## -----------------------------
#HTTP_CODE_FE=$(curl -s -o /dev/null -w "%{http_code}" https://$FE_URL/ || echo "000")
#if [ "$HTTP_CODE_FE" == "200" ]; then
#    echo "Frontend is UP ✅"
#else
#    echo "Frontend is DOWN ❌"
#fi

# -----------------------------
# Stream backend logs
# -----------------------------
echo "Streaming backend logs..."
az containerapp logs show -n $BACKEND -g $RG --tail 50 --follow
