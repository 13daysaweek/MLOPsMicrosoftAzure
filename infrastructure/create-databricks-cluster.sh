#!/bin/bash
set -e # force script to exit when a command fails
set -u # force script to exit when an undeclared variable is used
set -x # enable tracing


#TODO: AD SP creds need to be an input parameter
AAD_SP_CREDENTIALS=$(cat ../../aad-sp.json)

CLIENT_ID=$(echo $AAD_SP_CREDENTIALS | jq -r ".clientId")

CLIENT_SECRET=$(echo $AAD_SP_CREDENTIALS | jq -r ".clientSecret")

#TODO: tenanit id needs to be an input param
AAD_TOKEN_RESPONSE=$(curl -s -X GET -H 'Content-Type: application/x-www-form-urlencoded' -d "grant_type=client_credentials&client_id=$CLIENT_ID&resource=2ff814a6-3304-4ab8-85cb-cd0e6f879c1d&client_secret=$CLIENT_SECRET" https://login.microsoft.com/72f988bf-86f1-41af-91ab-2d7cd011db47/oauth2/token)

DATABRICKS_TOKEN=$(echo $AAD_TOKEN_RESPONSE | jq -r ".access_token")

#TODO: workspace and rg names need to be input parameters
WORKSPACE_ROOT_URL=$(az databricks workspace show -n amdb -g AUTUMN-ML-DEPLOY | jq -r ".workspaceUrl")

CREATE_CLUSTER_URL="https://$WORKSPACE_ROOT_URL/api/2.0/clusters/create"
echo $CREATE_CLUSTER_URL

WORKERS=8

#TODO: need input params for cluster name, spark version, node type, number of workers
CREATE_CLUSTER_BODY=$(jq -n --arg WORKERS "$WORKERS" '{
  "cluster_name": "my-cluster",
  "spark_version": "7.3.x-scala2.12",
  "node_type_id": "Standard_D3_v2",
  "spark_conf": {
    "spark.speculation": true
  },
  "num_workers": $WORKERS|tonumber
}')

curl -X POST -H 'Content-Type: application/json' -H 'Authorization: Bearer $DATABRICKS_TOKEN' -d "$CREATE_CLUSTER_BODY" $CREATE_CLUSTER_URL

