#!/bin/bash

source ./ups.env

PARAM="{
  \"user\":     \"${USER}\",
  \"password\": \"${PASSWORD}\",
  \"host\":     \"${HOST}\",
  \"port\":     \"${PORT}\",
  \"schema\":   \"${SCHEMA}\",
  \"driver\":   \"com.sap.db.jdbc.Driver\",
  \"tags\":     [\"hana\"]
}"

# Force delete the service if it exists
cf delete-service synonym-grantor-service -f

# Create the service
cf create-user-provided-service synonym-grantor-service -p "$PARAM"

# List the services
cf services