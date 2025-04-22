#!/bin/bash

# Exit script if a statement returns a non-true return value.
set -o errexit
# Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail
set -x

if [[ $OL_BUILD_ENV =~ "feature" ]]; then
  exit 0
fi

OL_HUB_API_KEY="$OPS_OL_HUB_API_KEY_PROD"
OL_HUB_API_LINK="api.ol-hub.com"

# Download solutions content thumbnails (as json)
curl --location --request POST "https://$OL_HUB_API_LINK/solution-center/api/v1/solutions/export-thumbnails" \
        --header 'Content-Type: application/json' --header "x-api-key: $OL_HUB_API_KEY" \
        -o "$HOME/project/db-migrations/hub-enterprise-db-migration/solutions-content.json"


