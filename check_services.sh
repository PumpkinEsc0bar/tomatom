#!/bin/bash
# Simple script to check if backend and frontend are alive

set -e

RESOURCE_GROUP="tomatom-rg"
BACKEND_NAME="tomatom-backend"
FRONTEND_NAME="tomatom-frontend"

BACKEND_URL=$(az containerapp show -n $BACKEND_NAME -g $RESOURCE_GROUP --query properties.configuration.ingress.fqdn -o tsv)
FRONTEND_URL=$(az containerapp show -n $FRONTEND_NAME -g $RESOURCE_GROUP --query properties.configuration.ingress.fqdn -o tsv)

echo "Checking backend..."
if curl -s -o /dev/null -w "%{http_code}" https://$BACKEND_URL/health | grep -q "200"; then
    echo "Backend is UP ✅"
else
    echo "Backend is DOWN ❌"
fi

echo "Checking frontend..."
if curl -s -o /dev/null -w "%{http_code}" https://$FRONTEND_URL/ | grep -q "200"; then
    echo "Frontend is UP ✅"
else
    echo "Frontend is DOWN ❌"
fi
