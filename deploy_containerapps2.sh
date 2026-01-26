#!/bin/bash
set -e

# -----------------------------
# Color definitions
# -----------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# -----------------------------
# Load .env
# -----------------------------
if [ ! -f .env ]; then
  echo -e "${RED}.env not found!${NC}"
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
echo -e "${CYAN}Logging in to Azure...${NC}"
az account show >/dev/null 2>&1 || az login
echo -e "${CYAN}Logging in to ACR...${NC}"
az acr login --name $ACR

# -----------------------------
# Build & push Docker images
# -----------------------------
echo -e "${BLUE}Building backend...${NC}"
docker build -t $ACR.azurecr.io/$BACKEND:latest ./backend
docker push $ACR.azurecr.io/$BACKEND:latest

# ----------------------------
# Check if backend container app exists
# ----------------------------
APP_EXISTS=$(az containerapp show \
  --name "$BACKEND" \
  --resource-group "$RG" \
  --query "name" -o tsv || echo "")

# ----------------------------
# Create or update backend
# ----------------------------
if [ -z "$APP_EXISTS" ]; then
  echo -e "${YELLOW}Backend container app does not exist. Creating...${NC}"
  az containerapp create \
    --name "$BACKEND" \
    --resource-group "$RG" \
    --environment "$ENV_NAME" \
    --image "$ACR.azurecr.io/$BACKEND:latest" \
    --cpu 0.5 \
    --memory 1.0Gi \
    --min-replicas 1 \
    --max-replicas 2 \
    --ingress 'external' \
    --target-port "$PORT" \
    --env-vars \
      AZURE_STORAGE_CONNECTION_STRING="$AZURE_STORAGE_CONNECTION_STRING" \
      EVENTHUB_NAMESPACE="$EVENTHUB_NAMESPACE" \
      EVENTHUB_CONNECTION_STRING="$EVENTHUB_CONNECTION_STRING" \
      RAW_CONTAINER_NAME="$RAW_CONTAINER_NAME" \
      PROCESSED_CONTAINER_NAME="$PROCESSED_CONTAINER_NAME" \
      EVENTHUB_NAME_UPLOADS="$EVENTHUB_NAME_UPLOADS" \
      KAFKA_TOPIC="$KAFKA_TOPIC" \
      NODE_ENV="$NODE_ENV" \
      PORT="$PORT" \
    --yes
  echo -e "${GREEN}Backend created successfully.${NC}"
else
  echo -e "${YELLOW}Backend container app exists. Updating image and env variables...${NC}"

  # Update image and resources
  az containerapp update \
    --name "$BACKEND" \
    --resource-group "$RG" \
    --image "$ACR.azurecr.io/$BACKEND:latest" \
    --cpu 0.5 \
    --memory 1.0Gi \
    --min-replicas 1 \
    --max-replicas 2 \
    --set-env-vars \
      AZURE_STORAGE_CONNECTION_STRING="$AZURE_STORAGE_CONNECTION_STRING" \
      EVENTHUB_NAMESPACE="$EVENTHUB_NAMESPACE" \
      EVENTHUB_CONNECTION_STRING="$EVENTHUB_CONNECTION_STRING" \
      RAW_CONTAINER_NAME="$RAW_CONTAINER_NAME" \
      PROCESSED_CONTAINER_NAME="$PROCESSED_CONTAINER_NAME" \
      EVENTHUB_NAME_UPLOADS="$EVENTHUB_NAME_UPLOADS" \
      KAFKA_TOPIC="$KAFKA_TOPIC" \
      NODE_ENV="$NODE_ENV" \
      PORT="$PORT"

  echo -e "${GREEN}Backend updated successfully.${NC}"
fi

# -----------------------------
# Deploy / Update frontend
# -----------------------------
BACKEND_FQDN=$(az containerapp show -n $BACKEND -g $RG --query properties.configuration.ingress.fqdn -o tsv)
echo -e "${MAGENTA}Backend FQDN: $BACKEND_FQDN${NC}"

# -----------------------------
# Build & push frontend Docker image with backend URL
# -----------------------------
echo -e "${BLUE}Building frontend...${NC}"
docker build \
  --build-arg REACT_APP_API_URL="https://$BACKEND_FQDN" \
  -t $ACR.azurecr.io/$FRONTEND:latest ./frontend
docker push $ACR.azurecr.io/$FRONTEND:latest

if ! az containerapp show -n $FRONTEND -g $RG >/dev/null 2>&1; then
  echo -e "${YELLOW}Creating frontend...${NC}"
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
  echo -e "${YELLOW}Updating frontend image...${NC}"
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
echo -e "${GREEN}Backend URL: https://$BE_URL${NC}"
echo -e "${GREEN}Frontend URL: https://$FE_URL${NC}"

# -----------------------------
# Wait for backend readiness
# -----------------------------
#echo -e "${CYAN}Checking backend readiness...${NC}"
#for i in {1..12}; do
#    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" https://$BE_URL/health || echo "000")
#    if [ "$HTTP_CODE" == "200" ]; then
#        echo -e "${GREEN}Backend is UP ✅${NC}"
#        break
#    else
#        echo -e "${YELLOW}Backend not ready yet (HTTP $HTTP_CODE), waiting 5s...${NC}"
#        sleep 5
#    fi
#done
#
## -----------------------------
## Check frontend
## -----------------------------
#HTTP_CODE_FE=$(curl -s -o /dev/null -w "%{http_code}" https://$FE_URL/ || echo "000")
#if [ "$HTTP_CODE_FE" == "200" ]; then
#    echo -e "${GREEN}Frontend is UP ✅${NC}"
#else
#    echo -e "${RED}Frontend is DOWN ❌${NC}"
#fi

# -----------------------------
# Stream backend logs
# -----------------------------
#echo -e "${CYAN}Streaming backend logs...${NC}"
#az containerapp logs show -n $BACKEND -g $RG --tail 50 --follow