#!/usr/bin/env bash
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
# Date: July 2019
# Purpose: Automate setup of the AutoML Demo for predicting Customer Lifetime Value - https://cloud.google.com/solutions/machine-learning/clv-prediction-with-automl-tables
set -o errexit
set -o pipefail
set -o nounset
#Debugging
set -o xtrace

. ./common.sh
PROGNAME=$(basename $0)

main() {
  local APIS="composer dataflow automl"
  enableAPIs $APIS

  PROJECT=$(gcloud config list project --format "value(core.project)")

  #Get the repo
  rm -rf tensorflow-lifetime-value
  git clone https://github.com/GoogleCloudPlatform/tensorflow-lifetime-value.git
  cd tensorflow-lifetime-value

  # Create the Service Accounts
  SVC_ACC_NAME=svcacc-clv-automl
  SVC_ACC_ROLES="roles/composer.worker roles/bigquery.dataEditor roles/bigquery.jobUser roles/storage.admin roles/ml.developer roles/dataflow.developer roles/compute.viewer roles/storage.objectAdmin roles/automl.editor"
  createServiceAccount

  # Install Miniconda
  installMiniConda

  # Create the Dev Environment
  createCondaEnv
  #source activate clv

  # Get into the AutoML folder
  pwd
  cd clv_automl
  local LOCAL_FOLDER=$(pwd)

  # Get the API key
  KEY_FILE=${LOCAL_FOLDER}/mykey.json
  rm -f $KEY_FILE
  echo "Creating JSON key file $KEY_FILE"
  gcloud iam service-accounts keys create $KEY_FILE --iam-account ${SVC_ACC_NAME}@${PROJECT}.iam.gserviceaccount.com
  cat $KEY_FILE
  export GOOGLE_APPLICATION_CREDENTIALS=${KEY_FILE}

  #train using AutoML
  python clv_automl.py --project_id ${PROJECT} --key_file ${KEY_FILE}

  #Remove Service Account Key
  removeServiceAccount
}

getData() {
  local BUCKET=gs://${PROJECT}_data_final
  local COMPOSER_NAME="clv-final"
  local COMPOSER_BUCKET_NAME=${PROJECT}_composer_final
  local COMPOSER_BUCKET=gs://${COMPOSER_BUCKET_NAME}
  local DF_STAGING=${COMPOSER_BUCKET}/dataflow_staging
  local DF_ZONE=${REGION}-a
  local SQL_MP_LOCATION="sql"
  #Beta v of AutomL Tables needs data to be in US only (Aug 2019)
  local REGION=us-central1
  local DATASET_NAME=ltv_edu_auto
  local TABLE_NAME=data_source

  # Copy the raw dataset
  gsutil -m rm -rf ${BUCKET}
  gsutil -m rm -rf ${COMPOSER_BUCKET}
  gsutil mb -l ${REGION} -p ${PROJECT} ${BUCKET}
  gsutil mb -l ${REGION} -p ${PROJECT} ${COMPOSER_BUCKET}
  gsutil cp gs://solutions-public-assets/ml-clv/db_dump.csv ${BUCKET}
  gsutil cp ${BUCKET}/db_dump.csv ${COMPOSER_BUCKET}

  # Copy the data to be predicted
  gsutil cp clv_automl/to_predict.csv ${BUCKET}/predictions/
  gsutil cp ${BUCKET}/predictions/to_predict.csv ${COMPOSER_BUCKET}/predictions/

  #Create bq dataset
  bq --location=US rm -rf --dataset ${PROJECT}:${DATASET_NAME}
  bq --location=US mk --dataset ${PROJECT}:${DATASET_NAME}
  bq mk -t --schema ../data_source.json ${PROJECT}:${DATASET_NAME}.${TABLE_NAME}
  echo "Loading raw dataset"
  bq --location=US load --source_format=CSV ${PROJECT}:${DATASET_NAME}.${TABLE_NAME} ${BUCKET}/db_dump.csv
  echo "Creating clean form of data"
  bq query --destination_table ${PROJECT}:${DATASET_NAME}.data_cleaned --use_legacy_sql=false < ../clean.sql
  echo "Creating features and targets"
  bq query --destination_table ${PROJECT}:${DATASET_NAME}.features_n_target --use_legacy_sql=false < ../features_n_target.sql
}

installMiniConda() {
  sudo apt-get install -y git bzip2
  if [ ! -f Miniconda2-latest-Linux-x86_64.sh ]
  then
    wget https://repo.continuum.io/miniconda/Miniconda2-latest-Linux-x86_64.sh
  fi

  if [ ! -d ~/miniconda2/ ]
  then
    bash Miniconda2-latest-Linux-x86_64.sh -b
  fi
  export PATH=~/miniconda2/bin:$PATH
}

createCondaEnv() {
  # Create the Dev Environment
  local EXISTS=$(conda env list | grep clv | wc -l)
  if [ ${EXISTS} -eq 0 ]
  then
    conda create -y -n clv
    conda install -y -n clv python=2.7 pip
  fi
  source activate clv
  pip install -r requirements.txt
}

createServiceAccount() {
  local EXISTS=$(gcloud iam service-accounts list | grep ${SVC_ACC_NAME}@${PROJECT}.iam.gserviceaccount.com | wc -l)
  echo $EXISTS
  if [ ${EXISTS} -eq 0 ]
  then
    # Create the Service Accounts
    gcloud iam service-accounts create $SVC_ACC_NAME --display-name $SVC_ACC_NAME --project ${PROJECT}
    echo "*** Adding Role Policy Bindings ***"
    declare -a roles=(${SVC_ACC_ROLES})
    for role in "${roles[@]}"
    do
      echo "Adding role: ${role} to service account $SVC_ACC_NAME"
      gcloud projects add-iam-policy-binding ${PROJECT} --member "serviceAccount:${SVC_ACC_NAME}@${PROJECT}.iam.gserviceaccount.com" --role "${role}" --quiet > /dev/null || true
    done
  fi
}

removeServiceAccount() {
  KEY=$(gcloud iam service-accounts keys list --iam-account $SVC_ACC_NAME@${PROJECT}.iam.gserviceaccount.com --managed-by user | grep -v KEY | xargs | cut -d " " -f 1)
  gcloud iam service-accounts keys delete ${KEY} --iam-account $SVC_ACC_NAME@${PROJECT}.iam.gserviceaccount.com  -q || true
  gcloud iam service-accounts delete $SVC_ACC_NAME@${PROJECT}.iam.gserviceaccount.com -q || true
  declare -a roles=(${SVC_ACC_ROLES})
  for role in "${roles[@]}"
  do
    echo "Removing role: ${role} to service account $SVC_ACC_NAME from $PROJECT"
    gcloud projects remove-iam-policy-binding ${PROJECT} --member "serviceAccount:${SVC_ACC_NAME}@${PROJECT}.iam.gserviceaccount.com" --role "${role}" --quiet > /dev/null || true
  done
}

trap 'abort ${LINENO} "$BASH_COMMAND' 0
SECONDS=0
main
trap : 0
printf "\n$PROGNAME complete in ${SECONDS} seconds.\n"
