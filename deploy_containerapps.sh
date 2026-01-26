#!/bin/bash
set -e

# Load env from .env
if [ ! -f .env ]; then
  echo ".env not found!"
  exit 1
fi
export $(grep -v '^#' .env | xargs)

# Azure settings
RG="tomatom-rg"
ACR="tomatomacr7080"
ENV_NAME="tomatom-env"
BACKEND="tomatom-backend"
FRONTEND="tomatom-frontend"

# Login
echo "Logging in to Azure..."
az account show >/dev/null 2>&1 || az login
echo "Logging in to ACR..."
az acr login --name $ACR

# Build & push
echo "Building backend..."
docker build -t $ACR.azurecr.io/$BACKEND:latest ./backend
docker push $ACR.azurecr.io/$BACKEND:latest

echo "Building frontend..."
docker build -t $ACR.azurecr.io/$FRONTEND:latest ./frontend
docker push $ACR.azurecr.io/$FRONTEND:latest

# Backend deploy
echo "Deploy backend..."
if ! az containerapp show -n $BACKEND -g $RG >/dev/null 2>&1; then
  az containerapp create \
    --name $BACKEND \
    --resource-group $RG \
    --environment $ENV_NAME \
    --image $ACR.azurecr.io/$BACKEND:latest \
    --target-port 8080 \
    --ingress external \
    --min-replicas 1 \
    --max-replicas 3 \
    --env-vars \
      PORT=$PORT \
      NODE_ENV=$NODE_ENV
else
  az containerapp update \
    --name $BACKEND \
    --resource-group $RG \
    --image $ACR.azurecr.io/$BACKEND:latest \
    --set-env-vars \
      PORT=$PORT \
      NODE_ENV=$NODE_ENV
fi

# Set additional backend env vars via set-env-vars
az containerapp update \
  --name $BACKEND \
  --resource-group $RG \
  --set-env-vars \
    AZURE_STORAGE_CONNECTION_STRING="$AZURE_STORAGE_CONNECTION_STRING" \
    EVENTHUB_NAMESPACE="$EVENTHUB_NAMESPACE" \
    EVENTHUB_CONNECTION_STRING="$EVENTHUB_CONNECTION_STRING" \
    RAW_CONTAINER_NAME="$RAW_CONTAINER_NAME" \
    PROCESSED_CONTAINER_NAME="$PROCESSED_CONTAINER_NAME" \
    EVENTHUB_NAME_UPLOADS="$EVENTHUB_NAME_UPLOADS" \
    KAFKA_TOPIC="$KAFKA_TOPIC"

# Frontend deploy
BACKEND_FQDN=$(az containerapp show -n $BACKEND -g $RG --query properties.configuration.ingress.fqdn -o tsv)

echo "Deploy frontend..."
if ! az containerapp show -n $FRONTEND -g $RG >/dev/null 2>&1; then
  az containerapp create \
    --name $FRONTEND \
    --resource-group $RG \
    --environment $ENV_NAME \
    --image $ACR.azurecr.io/$FRONTEND:latest \
    --target-port 80 \
    --ingress external \
    --min-replicas 1 \
    --max-replicas 3 \
    --env-vars \
      BACKEND_URL="https://$BACKEND_FQDN"
else
  az containerapp update \
    --name $FRONTEND \
    --resource-group $RG \
    --image $ACR.azurecr.io/$FRONTEND:latest \
    --set-env-vars \
      BACKEND_URL="https://$BACKEND_FQDN"
fi

# Show URLs
BE_URL=$(az containerapp show -n $BACKEND -g $RG --query properties.configuration.ingress.fqdn -o tsv)
FE_URL=$(az containerapp show -n $FRONTEND -g $RG --query properties.configuration.ingress.fqdn -o tsv)

echo "Backend: https://$BE_URL"
echo "Frontend: https://$FE_URL"

# Stream logs
echo "Streaming backend logs..."
az containerapp logs show -n $BACKEND -g $RG --tail 50 --follow
