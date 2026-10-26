#!/bin/bash

USER_NAME=${STUDENT_NUM}
NAMESPACE=${CLASS_NAME}

helm upgrade --install ${USER_NAME}-myfirst-helm 01.umbrella-chart \
  --namespace ${NAMESPACE} \
  --set global.userName=${USER_NAME}
