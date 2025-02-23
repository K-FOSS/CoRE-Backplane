#!/bin/bash

MACHINE_ID="${1:-kub-poc-control-plane-wxpf8}"
NAMESPACE="${2:-core-prod}"
IDRAC_SECRET=""

MACHINE_STATUS=$(kubectl get tinkerbellmachine.infrastructure.cluster.x-k8s.io -n ${NAMESPACE} ${MACHINE_ID} -o template  --template '{{ .status.ready }}')

function checkMachineStatus() {
    if [ "${MACHINE_STATUS}" != "true" ]; then
      echo "Hello"
      HW_ID=$(kubectl get tinkerbellmachine.infrastructure.cluster.x-k8s.io -n core-prod ${MACHINE_ID} -o template  --template '{{ .spec.hardwareName }}')
      NETBOOT_SCRIPT=$(kubectl get hardware.tinkerbell.org -n core-prod ${HW_ID} -o go-template  --template '{{ (index .spec.interfaces 0).netboot.ipxe.contents }}')
      kubectl patch hardware.tinkerbell.org -n ${NAMESPACE} ${HW_ID} --patch '{"spec": {"interfaces": [{ "netboot": { "ipxe": {}, "allowWorkflow": true  } }]}}'


      echo "Powering off the server"
      kubectl apply -f ./PowerOffAction.yaml

      echo "Server power off job has been issued, waiting 30 seconds before next action"
      sleep 30
      echo "30 Second period has ended, proceeding with the power on action"
      kubectl apply -f ./PowerOnAction.yaml

      echo "Waiting another 30 seconds and then script will end as nothing else has been programmed yet, you gotta GET GODD"
    else
        return 0 
    fi 
}



checkMachineStatus