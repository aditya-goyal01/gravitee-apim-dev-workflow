#!/bin/bash

# Gravitee APIM Developer Shell Aliases
# Source: https://github.com/gravitee-io/onboarding-resources

# --------------------------------------------------------------------------
# Docker commands
# --------------------------------------------------------------------------

# Run a MongoDB container with first parameter as a name: dmongo apim_3_21
dmongo() {
    docker run -p 27017:27017 --name "$1" -d mongo:7.0
}

# Run an Elasticsearch 7 container with first parameter as a name: des7 apim_3_21
des7() {
    docker run -d --name "$1" -p 9200:9200 -p 9300:9300 -e "discovery.type=single-node" docker.elastic.co/elasticsearch/elasticsearch:8.12.0
}

# Run a PostgreSQL container with first parameter as a name: dpostgres apim_3_21
dpostgres() {
    docker run -p 5432:5432 --env POSTGRES_HOST_AUTH_METHOD=trust --env POSTGRES_PASSWORD=pswd --env POSTGRES_USER=grvt --env POSTGRES_DB=gravitee --name "$1" -d postgres:16
}

# Stop a container with its name: dstop apim_3_21
dstop() {
    docker stop "$1"
}

# Remove a container with its name: drm apim_3_21
drm() {
    docker rm "$1"
}

# Stop and remove a container with its name: dkill apim_3_21
dkill() {
    docker stop "$1" && docker rm "$1"
}

# --------------------------------------------------------------------------
# Project directory
# --------------------------------------------------------------------------

export PROJECTS_DIR="$HOME/workspace/Gravitee"

# --------------------------------------------------------------------------
# Build aliases
# --------------------------------------------------------------------------

# Clean install (skip tests) with parallel threads
alias apimvn="mvn clean install -DskipTests=true -Dskip.validation -T 2C"

# Copy the zip of a plugin you just built into the gateway distribution folder
alias copy_plugin_gw="cp -v ./target/*.zip \$PROJECTS_DIR/gravitee-api-management/gravitee-apim-gateway/gravitee-apim-gateway-standalone/gravitee-apim-gateway-standalone-distribution/target/distribution/plugins"

# Copy the zip of a plugin you just built into the management API distribution folder
alias copy_plugin_rest="cp -v ./target/*.zip \$PROJECTS_DIR/gravitee-api-management/gravitee-apim-rest-api/gravitee-apim-rest-api-standalone/gravitee-apim-rest-api-standalone-distribution/target/distribution/plugins"

# Build a plugin and copy its zip into both gateway and management API distribution folders
alias plugin="apimvn && copy_plugin_gw && copy_plugin_rest"

# Build a plugin and copy its zip into the gateway distribution folder ONLY
alias gw_plugin="apimvn && copy_plugin_gw"

# Build a plugin and copy its zip into the management API distribution folder ONLY
alias rest_plugin="apimvn && copy_plugin_rest"

# --------------------------------------------------------------------------
# Formatting aliases
# --------------------------------------------------------------------------

# Run Prettier via Maven
alias mpw="mvn prettier:write"

# Run license header formatting via Maven
alias mlf="mvn license:format"
