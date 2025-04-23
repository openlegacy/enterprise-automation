#!/bin/bash

# Input parameters
LOCAL_FILE_PATH="./h3270-1.3.3.4.jar"
NAMESPACE="qa-team"  # If namespace is not provided, use "default"

if [ -z "$LOCAL_FILE_PATH" ]; then
    echo "Error: Please provide the local file path as an argument"
    echo "Usage: $0 <local_file_path> [namespace]"
    exit 1
fi

if [ ! -f "$LOCAL_FILE_PATH" ]; then
    echo "Error: File $LOCAL_FILE_PATH does not exist"
    exit 1
fi

# Get the pod name for hub-enterprise deployment
POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l app=hub-enterprise -o jsonpath='{.items[0].metadata.name}')


if [ -z "$POD_NAME" ]; then
    echo "Error: Could not find pod for hub-enterprise deployment"
    exit 1
fi

# Copy the file to the pod
echo "Found Pod: $POD_NAME"
echo "Found Pod: $NAMESPACE"
echo "Copying $LOCAL_FILE_PATH to $POD_NAME:/usr/app/lib/"
kubectl cp "$LOCAL_FILE_PATH" "$NAMESPACE/$POD_NAME:/usr/app/lib/"
kubectl cp "$LOCAL_FILE_PATH" "$NAMESPACE/$POD_NAME:/usr/app/lib/"

if [ $? -eq 0 ]; then
    echo "File successfully copied to the pod"
else
    echo "Error: Failed to copy file to the pod"
    exit 1
fi
