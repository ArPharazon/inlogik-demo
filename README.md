# InLogik demo

- [Introduction](#introduction)
- [Getting started](#getting-started)

## Introduction

This project demonstrates how to use Bicep to deploy a containerised .NET web application to Azure Container Apps.

The bicep template will deploy the following components:

- Azure Key Vault
- Azure Container Registry
- Azure Log Analytics Workspace
- Azure Application Insights
- Azure Container Apps Managed Environment
- Azure Container App

## Getting Started

### Pre-requisites

- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
- [Bicep tools](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/install)
- [Git](https://git-scm.com/downloads)
- [VSCode](https://code.visualstudio.com/), or your preferred code editor.

### Setup

```bash
# replace as needed
export APP_NAME=<>
export APP_IMAGE=<>
export APP_PORT=<>
export AZURE_RESOURCE_GROUP=<>
export AZURE_REGION=<>

az login

# get the default subscription id
subscriptionId=$(az account list --query "[?isDefault].id" -o tsv)

# Sets the current active subscription
az account set -s ${subscriptionId}

# create a suitable deployment name
current_datetime=$(date "+%Y%m%d_%H%M%S")
deployment_name=main_${current_datetime}

# check for any validation errors
az bicep lint --file ./infra/main.bicep

# create the resource group
az group create --name ${AZURE_RESOURCE_GROUP} --location ${AZURE_REGION}

# pre-deployment validation
az deployment group validate --name ${deployment_name} --resource-group ${AZURE_RESOURCE_GROUP} --parameters ./infra/main.bicepparam --query properties.outputs.fqdn

# create the deployment
az deployment group create --name ${deployment_name} --resource-group ${AZURE_RESOURCE_GROUP} --parameters ./infra/main.bicepparam --query properties.outputs.fqdn

```
