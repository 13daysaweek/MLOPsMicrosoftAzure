#!/bin/bash
set -e # force script to exit when a command fails
set -u # force script to exit when an undeclared variable is used
#set -x # uncomment to enable tracing.  WARNING: this will output things like auth tokens to the console, so don't use it in a real environment

# Parameters
# AAD-SP-CREDS a
# Databricks Workspace Name d
# Databricks resource id b
# Resource Group Name r
# Tenant ID t
# Cluster Name c
# Number of workers n
# Auto-termination minutes m
# Spark version s
while getopts a:d:r:t:c:n:m:s flag
do
  case "${flag} in
    a) AAD_SP_CREDENTIALS=${OPTARG};;
    d) DATABRICKS_WORKSPACE_NAME=${OPTARG};;
    b) DATABRICKS_RESOURCE_ID=${OPTARG};;
    r) RESOURCE_GROUP_NAME=${OPTARG};;
    t) TENANT_ID=${OPTARG};;
    c) CLUSTER_NAME=${OPTARG};;
    n) NUMBER_OF_WORKERS=${OPTARG};;
    m) AUTOTERMINATION_MINUTES=${OPTARG};;
    s) SPARK_VERSION=${OPTARG};;
  esac
done


#TODO: AD SP creds need to be an input parameter so we can source creds for a GH secret
AAD_SP_CREDENTIALS=$(cat ../../aad-sp.json)

CLIENT_ID=$(echo $AAD_SP_CREDENTIALS | jq -r ".clientId")

CLIENT_SECRET=$(echo $AAD_SP_CREDENTIALS | jq -r ".clientSecret")

#TODO: tenanit id needs to be an input param
AAD_TOKEN_RESPONSE=$(curl -s -X GET \
-H 'Content-Type: application/x-www-form-urlencoded' \
-d "grant_type=client_credentials&client_id=$CLIENT_ID&resource=2ff814a6-3304-4ab8-85cb-cd0e6f879c1d&client_secret=$CLIENT_SECRET" \
https://login.microsoft.com/72f988bf-86f1-41af-91ab-2d7cd011db47/oauth2/token)

DATABRICKS_TOKEN=$(echo $AAD_TOKEN_RESPONSE | jq -r ".access_token")

#TODO: workspace and rg names need to be input parameters
WORKSPACE_ROOT_URL=$(az databricks workspace show -n amdb -g AUTUMN-ML-DEPLOY | jq -r ".workspaceUrl")

MANAGEMENT_TOKEN_RESPONSE=$(curl -s -X GET \
-H 'Content-Type: application/x-www-form-urlencoded' \
-d "grant_type=client_credentials&client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET&resource=https%3A%2F%2Fmanagement.core.windows.net%2F" \
https://login.microsoft.com/72f988bf-86f1-41af-91ab-2d7cd011db47/oauth2/token)

MANAGEMENT_TOKEN=$(echo $MANAGEMENT_TOKEN_RESPONSE | jq -r ".access_token")

CREATE_CLUSTER_URL="https://$WORKSPACE_ROOT_URL/api/2.0/clusters/create"

#TODO: Needs to be an input param
WORKERS=16

#We don't know if the cluster config has changed, so instead of trying to determine if we need to update the cluster config, we'll delete and recreate

#First, list the clusters
CLUSTER_NAME="my-cluster"
LIST_CLUSTER_URL="https://$WORKSPACE_ROOT_URL/api/2.0/clusters/list"

CLUSTER_LIST_RESPONSE=$(curl -s -X GET \
-H "Authorization: Bearer $DATABRICKS_TOKEN" \
-H "X-Databricks-Azure-SP-Management-Token: $MANAGEMENT_TOKEN" \
-H "X-Databricks-Azure-Workspace-Resource-ID: /subscriptions/20032276-4660-477d-aefe-8379f2ab7c0d/resourceGroups/AUTUMN-ML-DEPLOY/providers/Microsoft.Databricks/workspaces/amdb" $LIST_CLUSTER_URL)

CLUSTERS_EXIST=$(echo $CLUSTER_LIST_RESPONSE | jq -c -r 'try .clusters[]')

if [ ! -z "$CLUSTERS_EXIST" ]
then
  echo "Found some existing clusters, checking to see if we need to delete one before creating"
  CLUSTER_ID=$(echo $CLUSTER_LIST_RESPONSE | jq -c -r --arg CLUSTER_NAME $CLUSTER_NAME '.clusters[] | select(.cluster_name == $CLUSTER_NAME) | .cluster_id')
  if [ ! -z $CLUSTER_ID ]
  then
    echo "Found a cluster with a name matching $CLUSTER_NAME, deleting it"
    DELETE_CLUSTER_URL="https://$WORKSPACE_ROOT_URL/api/2.0/clusters/permanent-delete"
    DELETE_CLUSTER_BODY=$(jq -n --arg CLUSTER_ID "$CLUSTER_ID" '{"cluster_id": $CLUSTER_ID}')

    curl -s -X POST \
    -H "Authorization: Bearer $DATABRICKS_TOKEN" \
    -H "X-Databricks-Azure-SP-Management-Token: $MANAGEMENT_TOKEN" \
    -H "X-Databricks-Azure-Workspace-Resource-ID: /subscriptions/20032276-4660-477d-aefe-8379f2ab7c0d/resourceGroups/AUTUMN-ML-DEPLOY/providers/Microsoft.Databricks/workspaces/amdb" \
    -H "Content-Type: application/json" \
    --data "$DELETE_CLUSTER_BODY" "$DELETE_CLUSTER_URL"
    echo "Cluster queued for deletion"
  else
    echo "Did not find a cluster with the name $CLUSTER_NAME"
  fi
else
  echo "No clusters found"
fi

#TODO: need input params for cluster name, spark version, node type, number of workers
CREATE_CLUSTER_BODY=$(jq -n --arg WORKERS "$WORKERS" '{
  "cluster_name": "my-cluster",
  "idempotency_token": "b0c66715-96dc-4000-b985-17b2bd169891",
  "spark_version": "7.3.x-scala2.12",
  "node_type_id": "Standard_D3_v2",
  "spark_conf": {
    "spark.speculation": true
  },
  "num_workers": $WORKERS|tonumber,
  "autotermination_minutes": 20
}')

#TODO: Need input parameter for workspace resource id
curl -s -X POST \
-H 'Content-Type: application/json' \
-H "Authorization: Bearer $DATABRICKS_TOKEN" \
-H "X-Databricks-Azure-SP-Management-Token: $MANAGEMENT_TOKEN" \
-H 'X-Databricks-Azure-Workspace-Resource-ID: /subscriptions/20032276-4660-477d-aefe-8379f2ab7c0d/resourceGroups/AUTUMN-ML-DEPLOY/providers/Microsoft.Databricks/workspaces/amdb' \
-d "$CREATE_CLUSTER_BODY" $CREATE_CLUSTER_URL
