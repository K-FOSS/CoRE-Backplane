#!/bin/bash

#
# Mode Options
# talosconfig
# kubeconfig
#
MODE="${1}"

case "${MODE}" in
  "talosconfig")
    echo "Getting Talos Config"
    
    CLUSTER_NAME="${2}"

    if [ -z "${CLUSTER_NAME}"  ]; then
      echo "Please provide a valid cluster name"
      exit 1
    fi

    kubectl get secret -n core-prod "${CLUSTER_NAME}-talosconfig" -o go-template='{{ .data.talosconfig | base64decode }}' > ./Meta/Configs/${CLUSTER_NAME}.talos
    ;;
  *)
    echo "Please provide a valid option of either talosconfig or kubeconfig"
    ;;
esac