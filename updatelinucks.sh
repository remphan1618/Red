#!/bin/bash

# Change to the workspace directory
cd /workspace/

# Cause the script to exit on failure.
set -eo pipefail

# Define the URL for the raw Jupyter Notebook file
NOTEBOOK_URL="https://raw.githubusercontent.com/remphan1618/Red/main/Modelgeddah.ipynb"
OUTPUT_FILENAME="Modelgeddah.ipynb"

# Download the notebook
echo "Downloading ${OUTPUT_FILENAME} from ${NOTEBOOK_URL} to /workspace/ ..."
if curl -sSL -o "${OUTPUT_FILENAME}" "${NOTEBOOK_URL}"; then
    echo "✅ Successfully downloaded ${OUTPUT_FILENAME} to /workspace/"
else
    echo "❌ Error: Failed to download ${OUTPUT_FILENAME}."
    # Attempt with wget as a fallback, if curl failed and wget is available
    if command -v wget &> /dev/null; then
        echo "Attempting download with wget..."
        if wget -O "${OUTPUT_FILENAME}" "${NOTEBOOK_URL}"; then
            echo "✅ Successfully downloaded ${OUTPUT_FILENAME} with wget to /workspace/"
        else
            echo "❌ Error: Failed to download ${OUTPUT_FILENAME} with wget as well."
            exit 1
        fi
    else
        exit 1
    fi
fi

# The script will now exit.
# All previous commands for pip installs, supervisor setup, etc., have been removed.