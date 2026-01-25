#!/bin/bash
set -e

# =========================
# Configuration
# =========================
RESOURCE_GROUP="tomatom-rg"
LOCATION="polandcentral"
ACR_NAME="tomatomacr7080"        # globally unique
ACA_ENV_NAME="tomatom-env"       # Azure Container Apps Managed Environment
BACKEND_NAME="tomatom-backend"
FRONTEND_NAME="tomatom-frontend"

# Load environment variables from .env
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

# =========================
# Azure CLI check
# =========================
if ! command -v az &>/dev/null; then
    echo "Azure CLI not installed!"
    exit 1
fi

# =========================
# Azure login
# =========================
if ! az account show &>/dev/null; then
    az login
fi

echo "Using subscription: $(az account show --query name -o tsv)"

# =========================
# Create Resource Group
# =========================
az group create --name $RESOURCE_GROUP --location $LOCATION

# =========================
# Login to ACR
# =========================
az acr login --name $ACR_NAME
ACR_URL="$ACR_NAME.azurecr.io"
ACR_USER=$(az acr credential show -n $ACR_NAME --query "username" -o tsv)
ACR_PASSWORD=$(az acr credential show -n $ACR_NAME --query "passwords[0].value" -o tsv)

# =========================
# Build & Push Backend
# =========================
echo "Building backend image..."
docker build -t $ACR_URL/backend:latest ./backend
docker push $ACR_URL/backend:latest

# =========================
# Deploy / Update Backend ACA
# =========================
if az containerapp show -n $BACKEND_NAME -g $RESOURCE_GROUP &>/dev/null; then
    echo "Updating backend containerapp..."
    az containerapp update \
        -n $BACKEND_NAME \
        -g $RESOURCE_GROUP \
        --image $ACR_URL/backend:latest
else
    echo "Creating backend containerapp..."
    az containerapp create \
        -n $BACKEND_NAME \
        -g $RESOURCE_GROUP \
        --environment $ACA_ENV_NAME \
        --image $ACR_URL/backend:latest \
        --ingress external \
        --target-port 8080 \
        --cpu 0.5 --memory 1.0Gi \
        --min-replicas 1 --max-replicas 2 \
        --registry-login-server $ACR_URL \
        --registry-username $ACR_USER \
        --registry-password $ACR_PASSWORD
fi

# =========================
# Get Backend external FQDN
# =========================
BACKEND_FQDN=$(az containerapp ingress show -n $BACKEND_NAME -g $RESOURCE_GROUP --query fqdn -o tsv)
echo "Backend external FQDN: $BACKEND_FQDN"

# =========================
# Build & Push Frontend with backend FQDN
# =========================
echo "Building frontend image with backend FQDN..."
docker build \
  --build-arg REACT_APP_API_URL="https://$BACKEND_FQDN" \
  -t $ACR_URL/frontend:latest \
  ./frontend

docker push $ACR_URL/frontend:latest

# =========================
# Deploy / Update Frontend ACA
# =========================
if az containerapp show -n $FRONTEND_NAME -g $RESOURCE_GROUP &>/dev/null; then
    echo "Updating frontend containerapp..."
    az containerapp update \
        -n $FRONTEND_NAME \
        -g $RESOURCE_GROUP \
        --image $ACR_URL/frontend:latest
else
    echo "Creating frontend containerapp..."
    az containerapp create \
        -n $FRONTEND_NAME \
        -g $RESOURCE_GROUP \
        --environment $ACA_ENV_NAME \
        --image $ACR_URL/frontend:latest \
        --ingress external \
        --target-port 80 \
        --cpu 0.5 --memory 1.0Gi \
        --min-replicas 1 --max-replicas 2 \
        --registry-login-server $ACR_URL \
        --registry-username $ACR_USER \
        --registry-password $ACR_PASSWORD
fi

# =========================
# Show final URLs
# =========================
FRONTEND_FQDN=$(az containerapp ingress show -n $FRONTEND_NAME -g $RESOURCE_GROUP --query fqdn -o tsv)

echo "✅ DEPLOY SUCCESSFUL"
echo "Frontend URL: https://$FRONTEND_FQDN"
echo "Backend URL: https://$BACKEND_FQDN"
