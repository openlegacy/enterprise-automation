#!/bin/bash

# Exit script if a statement returns a non-true return value.
set -o errexit
# Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail
set -x

bucket="bucket-for-download-portal"

# Check current core version
ol_core_revision=$(ciol getProperty --propertyKey openlegacyVersion)

# Copy dependencies to the correct folder in S3
echo "Copying runtime-m2-$ol_core_revision.zip to $bucket/hub-ent-installation S3 bucket"
aws s3 cp "s3://$bucket/runtime-m2-zip/$ol_core_revision/runtime-m2-$ol_core_revision.zip" \
    "s3://$bucket/hub-ent-installation/$OL_REVISION/runtime-m2-$ol_core_revision.zip"  \
    --acl bucket-owner-full-control \
    --profile "$AWS_ARTIFACTS_PROFILE"
