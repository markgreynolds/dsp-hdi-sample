#!/bin/bash

source ./ups.env

cf create-user-provided-service synonym-grantor-service -p '{
  "user":     "${USER}",
  "password": "${PASSWORD}",
  "host":     "${HOST}",
  "port":     "${PORT}",
  "schema":   "${SCHEMA}",
  "driver":   "com.sap.db.jdbc.Driver",
  "tags":     ["hana"]
}'

cf services
