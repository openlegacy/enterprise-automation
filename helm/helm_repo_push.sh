#!/bin/bash

#
# Sript to push helm chart to remote helm repository
#
# Usage: helm_repo_push.sh <REPO_USER> <REPO_PASSWORD> <CHART_NAME>
#

REPO_URL="https://openlegacy.jfrog.io/openlegacy/ol-hub-enterprise-helm"
REPO_USER=$1
REPO_PASSWORD=$2
CHART_NAME=$3
current_dir="$(basename "$(pwd)")"
index_file='index.yaml'

if [ "$CHART_NAME" == "" ]; then
    echo "Please define package name"
    exit 1
fi

if [[ $current_dir != $CHART_NAME ]]; then
    echo "Please run the script from chart directory:$CHART_NAME"
    exit 1
fi

echo 'Updating dependencies'
helm dependency update && \

echo "Packaging $CHART_NAME ..." && \
helm package . && \
PACKAGE_TAR=$(ls $CHART_NAME*.tgz) && \

echo "Downloading $index_file ..." && \
curl -su $REPO_USER:$REPO_PASSWORD -o "latest.$index_file" ${REPO_URL}/$index_file && \

echo "Updating $index_file ..." && \
helm repo index --merge "latest.$index_file" --url ${REPO_URL} . && \

echo "Uploading $CHART_NAME ..." && \
curl -u $REPO_USER:$REPO_PASSWORD --upload-file $PACKAGE_TAR "$REPO_URL/$PACKAGE_TAR" && \
echo "Uploading $index_file" && \
curl  -u ${REPO_USER}:${REPO_PASSWORD} --upload-file $index_file "$REPO_URL/$index_file" && \

# cleanup
rm -f $PACKAGE_TAR "latest.$index_file" $index_file
