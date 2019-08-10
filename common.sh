#!/bin/bash 
# Copyright 2018 Google LLC. This software is provided as-is, without warranty or representation for any use or purpose. Your use of it is subject to your agreements with Google.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# “Copyright 2018 Google LLC. This software is provided as-is, without warranty or representation for any use or purpose.
#  Your use of it is subject to your agreements with Google.”
#

# Author: Sufyaan Kazi
# Date: April 2018

## Enable GCloud APIS
enableAPIs() {
  if [ "$#" -eq 0 ]; then
    echo "Usage: $0 APIs" >&2
    echo "e.g. $0 iam compute" >&2
    exit 1
  fi

  #echo "Required apis for this project are: $@"
  declare -a REQ_APIS=(${@})

  local ENABLED_APIS=$(gcloud services list --enabled | grep -v NAME | sort | cut -d " " -f1)
  #echo "Current APIs enabled are: ${ENABLED_APIS}"

  for api in "${REQ_APIS[@]}"
  do
    #printf "\tChecking to see if ${api} api is enabled on this project\n"
    local API_EXISTS=$(echo ${ENABLED_APIS} | grep ${api}.googleapis.com | wc -l)
    if [ ${API_EXISTS} -eq 0 ]
    then
      echo "*** Enabling ${api} API"
      gcloud services enable "${api}.googleapis.com"
    fi
  done
}

# Creates a Service account, downloads the json key and exports this to the google
# application credentials environment variable
createServiceAccount() {
  if [ "$#" -lt 4 ]; then
    echo "Usage: $0 SERVICE_ACC_NAME PROJECT_ID KEY_FILE SERVICE_ACC_ROLES" >&2
    echo "e.g. $0 nlp-service-acc myproj123 ~/keys/nlp-service-acc.json roles/viewer" >&2
    echo "e.g. $0 nlp-service-acc myproj123 ~/keys/nlp-service-acc.json roles/monitoring.viewer roles/stackdriver.accounts.viewer" >&2
    exit 1
  fi
  
  local SERVICE_ACC_NAME=$1
  local PROJECT_ID=$2
  local SERVICE_ACC=${SERVICE_ACC_NAME}@${PROJECT_ID}
  local KEY_FILE=$3
  local SERVICE_ACC_ROLES="${@:4}"

  #Does the service account key file exist locally?
  if [ -f ${KEY_FILE} ]
  then
    echo "Local copy of $KEY_FILE found, so it will be used"
    export GOOGLE_APPLICATION_CREDENTIALS=${KEY_DIR}/${KEY_FILE}
    echo GOOGLE_APPLICATION_CREDENTIAL=${GOOGLE_APPLICATION_CREDENTIALS}
    return 0
  fi

  # Otherwise, check if the service account exists or not?
  local EXISTING_SERVICE_ACC_COUNT=$(gcloud iam service-accounts list | cut -d " " -f1 | grep $SERVICE_ACC_NAME | wc -l)
  if [ ${EXISTING_SERVICE_ACC_COUNT} -ne 0 ]
  then
    echo "$SERVICE_ACC_NAME exists already so not creating again"
  else
    ## Create the Service Account
    echo "Creating service account $SERVICE_ACC_NAME"
    gcloud iam service-accounts create $SERVICE_ACC_NAME --display-name=$SERVICE_ACC_NAME

    # Add Role Policy Bindings
    declare -a roles=(${SERVICE_ACC_ROLES})
    for role in "${roles[@]}"
    do
      printf "\tAdding role: ${role} to service account $SERVICE_ACC_NAME in project ${PROJECT_ID}\n"
      gcloud projects add-iam-policy-binding ${PROJECT_ID} --member "serviceAccount:${SERVICE_ACC}.iam.gserviceaccount.com" --role "${role}" --quiet
    done
  fi

  # create the key file
  echo "Creating JSON key file $KEY_FILE"
  gcloud iam service-accounts keys create $KEY_FILE --iam-account ${SERVICE_ACC}.iam.gserviceaccount.com
  gcloud auth activate-service-account --key-file $KEY_FILE

  #Store the key in env variable
  export GOOGLE_APPLICATION_CREDENTIALS=${KEY_FILE}
  echo ${GOOGLE_APPLICATION_CREDENTIALS}
  echo GOOGLE_APPLICATION_CREDENTIAL=${GOOGLE_APPLICATION_CREDENTIALS}
}

#
# Handle an error in the script
#
abort()
{
  echo >&2 '
  ***************
  *** ABORTED ***
  ***************
  '
  echo "An error occurred. Exiting..." >&2
  echo "${PROGNAME}: ${1:-"Unknown Error"}" 1>&2
  exit 1
}
