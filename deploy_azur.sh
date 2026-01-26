#!/bin/bash
set -e

# =========================
# Configuration
# =========================
RESOURCE_GROUP="tomatom-rg"
LOCATION="polandcentral"
PLAN_NAME="tomatom-p"
APP_NAME="tomatom-web"
ACR_NAME="tomatomacr$RANDOM"  # must be globally unique
DOCKER_COMPOSE_FILE="docker-compose.azure.yml"

# Load environment variables from .env
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

# =========================
# Azure CLI check
# =========================
if ! command -v az &> /dev/null; then
    echo "Azure CLI is not installed."
    exit 1
fi

# =========================
# Azure login
# =========================
if ! az account show &> /dev/null; then
    az login
fi

echo "Using subscription: $(az account show --query name -o tsv)"

# =========================
# Create Resource Group
# =========================
echo "Creating resource group $RESOURCE_GROUP..."
az group create --name $RESOURCE_GROUP --location $LOCATION

# =========================
# Create App Service Plan
# =========================
echo "Creating App Service plan $PLAN_NAME..."
az appservice plan create \
    --name $PLAN_NAME \
    --resource-group $RESOURCE_GROUP \
    --is-linux \
    --sku B1

# =========================
# Create Azure Container Registry (ACR)
# =========================
echo "Creating Azure Container Registry $ACR_NAME..."
az acr create \
    --resource-group $RESOURCE_GROUP \
    --name $ACR_NAME \
    --sku Basic \
    --admin-enabled true

# Login to ACR
az acr login --name $ACR_NAME

# Get admin username and password
ACR_USER=$(az acr credential show -n $ACR_NAME --query "username" -o tsv)
ACR_PASSWORD=$(az acr credential show -n $ACR_NAME --query "passwords[0].value" -o tsv)

# =========================
# Build and push Docker images
# =========================
echo "Building and pushing backend image..."
docker build -t $ACR_NAME.azurecr.io/backend:latest ./backend
docker push $ACR_NAME.azurecr.io/backend:latest

echo "Building and pushing frontend image..."
docker build -t $ACR_NAME.azurecr.io/frontend:latest ./frontend
docker push $ACR_NAME.azurecr.io/frontend:latest

# =========================
# Generate docker-compose for Azure
# =========================
cat > $DOCKER_COMPOSE_FILE << EOF
version: '3.8'

services:
  backend:
    image: $ACR_NAME.azurecr.io/backend:latest
    environment:
      AZURE_STORAGE_CONNECTION_STRING: ${AZURE_STORAGE_CONNECTION_STRING}
      EVENTHUB_NAMESPACE: ${EVENTHUB_NAMESPACE}
      EVENTHUB_CONNECTION_STRING: ${EVENTHUB_CONNECTION_STRING}
      EVENTHUB_NAME_UPLOADS: image-uploads
      KAFKA_BROKERS: \${EVENTHUB_NAMESPACE}.servicebus.windows.net:9093
      KAFKA_SASL_USERNAME: \$ConnectionString
      KAFKA_SASL_PASSWORD: \${EVENTHUB_CONNECTION_STRING}
      KAFKA_SASL_MECHANISM: PLAIN
      KAFKA_SECURITY_PROTOCOL: SASL_SSL
      RAW_CONTAINER_NAME: recipe-raw-images
      PROCESSED_CONTAINER_NAME: recipe-processed-images
      NODE_ENV: production
      PORT: 8080
      KAFKA_TOPIC: image-uploads
    ports:
      - "8080:8080"

  frontend:
    image: $ACR_NAME.azurecr.io/frontend:latest
    environment:
      REACT_APP_API_URL: https://$APP_NAME.azurewebsites.net
    ports:
      - "80:80"
    depends_on:
      - backend
EOF

# =========================
# Create Web App (multi-container)
# =========================
echo "Creating Web App $APP_NAME..."
az webapp create \
    --resource-group $RESOURCE_GROUP \
    --plan $PLAN_NAME \
    --name $APP_NAME \
    --multicontainer-config-type compose \
    --multicontainer-config-file $DOCKER_COMPOSE_FILE

# =========================
# Link Web App to ACR for private image pull
# =========================
echo "Configuring ACR access for Web App..."
az webapp config container set \
    --name $APP_NAME \
    --resource-group $RESOURCE_GROUP \
    --docker-registry-server-url https://$ACR_NAME.azurecr.io \
    --docker-registry-server-user $ACR_USER \
    --docker-registry-server-password $ACR_PASSWORD

echo "Deployment completed!"
echo "Frontend URL: https://$APP_NAME.azurewebsites.net"
