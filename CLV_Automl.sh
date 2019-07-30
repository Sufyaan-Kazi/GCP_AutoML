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
# Date: July 2019
# Purpose: Automate setup of the AutoML Demo for predicting Customer Lifetime Value - https://cloud.google.com/solutions/machine-learning/clv-prediction-with-automl-tables

. ./common.sh

main() {
  local APIS="composer dataflow automl"
  local PROJECT=$(gcloud config list project --format "value(core.project)")
  local SCRIPT_NAME=clv-automl
  local SERVICE_ACC=svcacc-$SVC_ACC_NAME@$PROJECT
  local KEY_FILE=$SERVICE_ACC.json
  local ROLES=roles/viewer

  rm Minic*

  #Enable required GCP apis
  enableAPIs $APIS
  printf "******\n\n"

  # Install Miniconda
  sudo apt-get install -y git bzip2
  wget https://repo.continuum.io/miniconda/Miniconda2-latest-Linux-x86_64.sh
  bash Miniconda2-latest-Linux-x86_64.sh -b
  local PATH=~/miniconda2/bin:$PATH

  #Get the repo
  git clone https://github.com/GoogleCloudPlatform/tensorflow-lifetime-value.git
  cd tensorflow-lifetime-value

  # Create the Dev Environment
  conda create -y -n clv
  source activate clv
  conda install -y -n clv python=2.7 pip
  pip install -r requirements.txt

  #Setup environment for Airflow
  local BUCKET=gs://${PROJECT}_data_final
  local REGION=europe-west1
  local DATASET_NAME=ltv
  local TABLE_NAME=data_source

  local COMPOSER_NAME="clv-final"
  local COMPOSER_BUCKET_NAME=${PROJECT}_composer_final
  local COMPOSER_BUCKET=gs://${COMPOSER_BUCKET_NAME}
  local DF_STAGING=${COMPOSER_BUCKET}/dataflow_staging
  local DF_ZONE=${REGION}-a
  local SQL_MP_LOCATION="sql"

  local LOCAL_FOLDER=$(pwd)

  # Copy the raw dataset
  gsutil cp gs://solutions-public-assets/ml-clv/db_dump.csv ${BUCKET}
  gsutil cp ${BUCKET}/db_dump.csv ${COMPOSER_BUCKET}

  # Copy the data to be predicted
  gsutil cp clv_automl/to_predict.json ${BUCKET}/predictions/
  gsutil cp ${BUCKET}/predictions/to_predict.json ${COMPOSER_BUCKET}/predictions/
  gsutil cp clv_automl/to_predict.csv ${BUCKET}/predictions/
  gsutil cp ${BUCKET}/predictions/to_predict.csv ${COMPOSER_BUCKET}/predictions/

  # Create the Service Accounts
  SVC_ACC_NAME=svcacc-$SCRIPT_NAME
  gcloud iam service-accounts create $SVC_ACC_NAME --display-name $SVC_ACC_NAME --project ${PROJECT}

  gcloud projects add-iam-policy-binding ${PROJECT} \
  --member serviceAccount:$SVC_ACC_NAME@${PROJECT}.iam.gserviceaccount.com \
  --role roles/composer.worker

  gcloud projects add-iam-policy-binding ${PROJECT} \
  --member serviceAccount:$SVC_ACC_NAME@${PROJECT}.iam.gserviceaccount.com \
  --role roles/bigquery.dataEditor

  gcloud projects add-iam-policy-binding ${PROJECT} \
  --member serviceAccount:$SVC_ACC_NAME@${PROJECT}.iam.gserviceaccount.com \
  --role roles/bigquery.jobUser

  gcloud projects add-iam-policy-binding ${PROJECT} \
  --member serviceAccount:$SVC_ACC_NAME@${PROJECT}.iam.gserviceaccount.com \
  --role roles/storage.admin

  gcloud projects add-iam-policy-binding ${PROJECT} \
  --member serviceAccount:$SVC_ACC_NAME@${PROJECT}.iam.gserviceaccount.com \
  --role roles/ml.developer

  gcloud projects add-iam-policy-binding ${PROJECT} \
  --member serviceAccount:$SVC_ACC_NAME@${PROJECT}.iam.gserviceaccount.com \
  --role roles/dataflow.developer

  gcloud projects add-iam-policy-binding ${PROJECT} \
  --member serviceAccount:$SVC_ACC_NAME@${PROJECT}.iam.gserviceaccount.com \
  --role roles/compute.viewer

  gcloud projects add-iam-policy-binding ${PROJECT} \
  --member serviceAccount:$SVC_ACC_NAME@${PROJECT}.iam.gserviceaccount.com \
  --role roles/storage.objectAdmin

  gcloud projects add-iam-policy-binding ${PROJECT} \
  --member serviceAccount:$SVC_ACC_NAME@${PROJECT}.iam.gserviceaccount.com \
  --role='roles/automl.editor'

  # Get the API key
  KEY_FILE=mykey.json
  echo "Creating JSON key file $KEY_FILE"
  gcloud iam service-accounts keys create $KEY_FILE --iam-account ${SVC_ACC_NAME}@${PROJECT}.iam.gserviceaccount.com
  #gcloud auth activate-service-account --key-file $KEY_FILE

  #Store the key in env variable
  export GOOGLE_APPLICATION_CREDENTIALS=${KEY_FILE}
  echo ${GOOGLE_APPLICATION_CREDENTIALS}
  echo GOOGLE_APPLICATION_CREDENTIAL=${GOOGLE_APPLICATION_CREDENTIALS} 

  #Setup & load Data in BigQuery
  gsutil mb -l ${REGION} -p ${PROJECT} ${BUCKET}
  gsutil mb -l ${REGION} -p ${PROJECT} ${COMPOSER_BUCKET}
  bq --location=EU rm -rf --dataset ${PROJECT}:${DATASET_NAME}
  bq --location=EU mk --dataset ${PROJECT}:${DATASET_NAME}
  bq mk -t --schema data_source.json ${PROJECT}:${DATASET_NAME}
  bq --location=EU load --source_format=CSV ${PROJECT}:${DATASET_NAME}.$TABLE_NAME} ${BUCKET}/db_dump.csv

  #train using AutoML
  cd ${LOCAL_FOLDER}/clv_automl
  cat clv_automl.py | sed -e 's/us-central1/europe-west1/g' > clv_automl.py
  python clv_automl.py --project_id ${PROJECT}
}

main
