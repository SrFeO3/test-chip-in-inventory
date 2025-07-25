#!/bin/bash

# This script provides common helper functions and variables for other test scripts.

# --- Exit on error ---
set -e
set -o pipefail

# --- Helper Functions ---
step() { echo -e "\n\n\e[1;34m>>> $1\e[0m"; }
ok() { echo -e "\e[32mOK: $1\e[0m"; }
fail() { echo -e "\e[1;31mFAIL: $1\e[0m"; exit 1; }
check_jq() {
    if ! command -v jq &> /dev/null; then
        echo "jq could not be found, please install it to run the tests."
        exit 1
    fi
}

# --- Common Configuration ---
API_BASE_URL="http://127.0.0.1:8080"
REALM_NAME="test-realm"

export API_BASE_URL REALM_NAME