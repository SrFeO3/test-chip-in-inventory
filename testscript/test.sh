#!/bin/bash
set -e

# This is the main test runner script.
# It executes all other test scripts in order.

source ./test_helper.sh

step "Starting All Tests"

step "Running Realm tests..."
./test_realm.sh
ok "Realm tests passed."

step "Running Zone tests..."
./test_zone.sh
ok "Zone tests passed."

step "Running Subdomain tests..."
./test_subdomain.sh
ok "Subdomain tests passed."

step "Running RoutingChain tests..."
./test_routing_chain.sh
ok "RoutingChain tests passed."

step "Running VirtualHost tests..."
./test_virtual_host.sh
ok "VirtualHost tests passed."

step "Running Hub tests..."
./test_hub.sh
ok "Hub tests passed."

step "Running Service tests..."
./test_service.sh
ok "Service tests passed."

step "\e[1;32mAll API tests passed successfully!\e[0m"