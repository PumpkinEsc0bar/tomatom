#!/bin/bash

# Azure Recipe Manager Deployment Script
# This script automates the creation of Azure resources

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
RESOURCE_GROUP="tomatom-rg"
LOCATION="polandcentral"
STORAGE_ACCOUNT="tomastorageacc$RANDOM"
EVENTHUB_NAMESPACE="toma-eventhub-ns$RANDOM"
EVENTHUB_NAME="image-uploads"

echo -e "${GREEN}=== Azure Recipe Manager Deployment ===${NC}"
echo ""

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    echo -e "${RED}Error: Azure CLI is not installed${NC}"
    echo "Please install it from: https://docs.microsoft.com/cli/azure/install-azure-cli"
    exit 1
fi

# Login check
echo -e "${YELLOW}Checking Azure login status...${NC}"
if ! az account show &> /dev/null; then
    echo -e "${YELLOW}Please login to Azure:${NC}"
    az login
fi

SUBSCRIPTION=$(az account show --query name -o tsv)
echo -e "${GREEN}Using subscription: ${SUBSCRIPTION}${NC}"
echo ""

# Create Resource Group
echo -e "${YELLOW}Creating Resource Group...${NC}"
az group create \
    --name $RESOURCE_GROUP \
    --location $LOCATION \
    --output table

echo -e "${GREEN}✓ Resource Group created${NC}"
echo ""

# Create Storage Account
echo -e "${YELLOW}Creating Storage Account...${NC}"
az storage account create \
    --name $STORAGE_ACCOUNT \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION \
    --sku Standard_LRS \
    --kind StorageV2 \
    --access-tier Hot \
    --allow-blob-public-access true \
    --output table

echo -e "${GREEN}✓ Storage Account created: ${STORAGE_ACCOUNT}${NC}"
echo ""

# Get Storage Connection String
echo -e "${YELLOW}Getting Storage Connection String...${NC}"
STORAGE_CONNECTION_STRING=$(az storage account show-connection-string \
    --name $STORAGE_ACCOUNT \
    --resource-group $RESOURCE_GROUP \
    --output tsv)

echo -e "${GREEN}✓ Storage Connection String retrieved${NC}"
echo ""

# Get Storage Key
STORAGE_KEY=$(az storage account keys list \
    --account-name $STORAGE_ACCOUNT \
    --resource-group $RESOURCE_GROUP \
    --query '[0].value' -o tsv)

# Create Blob Containers
echo -e "${YELLOW}Creating Blob Containers...${NC}"
az storage container create \
    --name recipe-raw-images \
    --account-name $STORAGE_ACCOUNT \
    --account-key $STORAGE_KEY \
    --public-access blob \
    --output table

az storage container create \
    --name recipe-processed-images \
    --account-name $STORAGE_ACCOUNT \
    --account-key $STORAGE_KEY \
    --public-access blob \
    --output table

echo -e "${GREEN}✓ Blob Containers created${NC}"
echo ""

# Create Event Hubs Namespace
echo -e "${YELLOW}Creating Event Hubs Namespace (this may take a few minutes)...${NC}"
az eventhubs namespace create \
    --name $EVENTHUB_NAMESPACE \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION \
    --sku Standard \
    --enable-kafka true \
    --output table

echo -e "${GREEN}✓ Event Hubs Namespace created: ${EVENTHUB_NAMESPACE}${NC}"
echo ""

# Wait until Event Hubs Namespace is Succeeded
echo -e "${YELLOW}Waiting for Event Hubs Namespace to be ready...${NC}"
until [[ $(az eventhubs namespace show --name $EVENTHUB_NAMESPACE --resource-group $RESOURCE_GROUP --query "provisioningState" -o tsv) == "Succeeded" ]]; do
    echo -e "${YELLOW}Namespace not ready yet, waiting 10 seconds...${NC}"
    sleep 10
done

echo -e "${GREEN}✓ Event Hubs Namespace is ready${NC}"
echo ""

# Create Event Hub
echo -e "${YELLOW}Creating Event Hub...${NC}"
az eventhubs eventhub create \
    --name $EVENTHUB_NAME \
    --resource-group $RESOURCE_GROUP \
    --namespace-name $EVENTHUB_NAMESPACE \
    --partition-count 3 \
    --output table

echo -e "${GREEN}✓ Event Hub created: ${EVENTHUB_NAME}${NC}"
echo ""

# Get Event Hub Connection String
echo -e "${YELLOW}Getting Event Hub Connection String...${NC}"

# Wait until keys are available
until EVENTHUB_CONNECTION_STRING=$(az eventhubs namespace authorization-rule keys list \
    --resource-group $RESOURCE_GROUP \
    --namespace-name $EVENTHUB_NAMESPACE \
    --name RootManageSharedAccessKey \
    --query primaryConnectionString \
    --output tsv) || [ -z "$EVENTHUB_CONNECTION_STRING" ]; do
    echo -e "${YELLOW}Connection string not ready yet, waiting 5 seconds...${NC}"
    sleep 5
done

echo -e "${GREEN}✓ Event Hub Connection String retrieved${NC}"

# Create .env file
echo -e "${YELLOW}Creating .env file...${NC}"
cat > .env << EOF
# Azure Storage Account
AZURE_STORAGE_CONNECTION_STRING=${STORAGE_CONNECTION_STRING}

# Azure Event Hubs
EVENTHUB_NAMESPACE=${EVENTHUB_NAMESPACE}
EVENTHUB_CONNECTION_STRING=${EVENTHUB_CONNECTION_STRING}

# Container Names
RAW_CONTAINER_NAME=recipe-raw-images
PROCESSED_CONTAINER_NAME=recipe-processed-images

# Event Hub Name
EVENTHUB_NAME_UPLOADS=${EVENTHUB_NAME}
KAFKA_TOPIC=${EVENTHUB_NAME}

# Application Settings
PORT=8080
NODE_ENV=production
EOF

echo -e "${GREEN}✓ .env file created${NC}"
echo ""

# Summary
echo -e "${GREEN}=== Deployment Summary ===${NC}"
echo ""
echo -e "Resource Group:        ${GREEN}${RESOURCE_GROUP}${NC}"
echo -e "Location:              ${GREEN}${LOCATION}${NC}"
echo -e "Storage Account:       ${GREEN}${STORAGE_ACCOUNT}${NC}"
echo -e "Event Hub Namespace:   ${GREEN}${EVENTHUB_NAMESPACE}${NC}"
echo -e "Event Hub:             ${GREEN}${EVENTHUB_NAME}${NC}"
echo ""
echo -e "${YELLOW}Raw Images Container:       ${NC}recipe-raw-images"
echo -e "${YELLOW}Processed Images Container: ${NC}recipe-processed-images"
echo ""
echo -e "${GREEN}=== Next Steps ===${NC}"
echo ""
echo "1. Review the generated .env file"
echo "2. Build and run the application:"
echo "   ${YELLOW}docker compose up --build${NC}"
echo ""
echo "3. Test the upload endpoint:"
echo "   ${YELLOW}curl -X POST http://localhost:8080/api/upload -F \"image=@/path/to/image.jpg\"${NC}"
echo ""
echo "4. View logs:"
echo "   ${YELLOW}docker compose logs -f backend${NC}"
echo ""
echo -e "${GREEN}Deployment completed successfully!${NC}"
echo ""

# Optional: Display resource URLs
echo -e "${GREEN}=== Azure Portal URLs ===${NC}"
echo ""
echo "Storage Account:"
echo "https://portal.azure.com/#@/resource/subscriptions/$(az account show --query id -o tsv)/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCOUNT}"
echo ""
echo "Event Hubs:"
echo "https://portal.azure.com/#@/resource/subscriptions/$(az account show --query id -o tsv)/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.EventHub/namespaces/${EVENTHUB_NAMESPACE}"
echo ""
