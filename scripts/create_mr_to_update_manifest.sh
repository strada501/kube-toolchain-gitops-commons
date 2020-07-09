#!/bin/bash
# uncomment to debug the script
# set -x
# This script does push the new manifest file which is update with the latest Docker image.
# Minting image tag using format: BUILD_NUMBER-BRANCH-COMMIT_ID-TIMESTAMP

# Input env variables (can be received via a pipeline environment properties.file.
echo "ARCHIVE_DIR=${ARCHIVE_DIR}"
echo "DEPLOYMENT_FILE=${DEPLOYMENT_FILE}"
echo "DEPLOYMENT_FILE_ADDITIONAL=${DEPLOYMENT_FILE_ADDITIONAL}"
echo "GIT_COMMIT=${GIT_COMMIT}"
echo "GIT_USER_EMAIL=${GIT_USER_EMAIL}"
echo "GIT_USER_NAME=${GIT_USER_NAME}"
echo "GITLAB_DOMAIN=${GITLAB_DOMAIN}"
echo "GITLAB_GROUP_NAME=${GITLAB_GROUP_NAME}"
echo "GITLAB_OPS_PROJECT_NAME=${GITLAB_OPS_PROJECT_NAME}"
echo "GITLAB_OPS_PROJECT_ID=${GITLAB_OPS_PROJECT_ID}"
echo "SOURCE_BRANCH_NAME=${SOURCE_BRANCH_NAME}"
echo "TARGET_BRANCH_NAME=${TARGET_BRANCH_NAME}"

# If running after build_image.sh in same stage, reuse the exported variable PIPELINE_IMAGE_URL
if [ -z "${PIPELINE_IMAGE_URL}" ]; then
  PIPELINE_IMAGE_URL=${REGISTRY_URL}/${REGISTRY_NAMESPACE}/${IMAGE_NAME}:${IMAGE_TAG}
else
  # extract from img url
  REGISTRY_URL=$(echo ${PIPELINE_IMAGE_URL} | cut -f1 -d/)
  REGISTRY_NAMESPACE=$(echo ${PIPELINE_IMAGE_URL} | cut -f2 -d/)
  IMAGE_NAME=$(echo ${PIPELINE_IMAGE_URL} | cut -f3 -d/ | cut -f1 -d:)
  IMAGE_TAG=$(echo ${PIPELINE_IMAGE_URL} | cut -f3 -d/ | cut -f2 -d:)
fi
echo "PIPELINE_IMAGE_URL=${PIPELINE_IMAGE_URL}"
echo "REGISTRY_URL=${REGISTRY_URL}"
echo "REGISTRY_NAMESPACE=${REGISTRY_NAMESPACE}"
echo "IMAGE_NAME=${IMAGE_NAME}"
echo "IMAGE_TAG=${IMAGE_TAG}"

# Push build.properites to the gitlab infrastructure repository.
echo "Push manifest file to the gitlab infrastructure repository."

git config --global user.email "${GIT_USER_EMAIL}"
git config --global user.name "${GIT_USER_NAME}"
git clone https://oauth2:"${GITLAB_ACCESS_TOKEN}"@${GITLAB_DOMAIN}/${GITLAB_GROUP_NAME}/${GITLAB_OPS_PROJECT_NAME}.git

cd $GITLAB_OPS_PROJECT_NAME

if [ -z ${DEPLOYMENT_FILE_ADDITIONAL} ];then
  git checkout -b $SOURCE_BRANCH_NAME
fi

echo "=========================================================="
echo "UPDATING manifest with image information"
IMAGE_REPOSITORY=${REGISTRY_URL}/${REGISTRY_NAMESPACE}/${IMAGE_NAME}
echo -e "Updating ${DEPLOYMENT_FILE} with image name: ${IMAGE_REPOSITORY}:${IMAGE_TAG}"
NEW_DEPLOYMENT_FILE="$(dirname $DEPLOYMENT_FILE)/tmp.$(basename $DEPLOYMENT_FILE)"
# find the yaml document index for the K8S deployment definition
DEPLOYMENT_DOC_INDEX=$(yq read --doc "*" --tojson $DEPLOYMENT_FILE | jq -r 'to_entries | .[] | select(.value.kind | ascii_downcase=="deployment") | .key')
if [ -z "$DEPLOYMENT_DOC_INDEX" ]; then
  echo "No Kubernetes Deployment definition found in $DEPLOYMENT_FILE. Updating YAML document with index 0"
  DEPLOYMENT_DOC_INDEX=0
fi
# Update deployment with image name
yq write $DEPLOYMENT_FILE --doc $DEPLOYMENT_DOC_INDEX "spec.template.spec.containers[0].image" "${REGISTRY_URL}/${REGISTRY_NAMESPACE}/${IMAGE_NAME}:${IMAGE_TAG}" > ${NEW_DEPLOYMENT_FILE}
mv -f ${NEW_DEPLOYMENT_FILE} ${DEPLOYMENT_FILE}
cat ${DEPLOYMENT_FILE}

# Update additional deployment with image name
if [ "${DEPLOYMENT_FILE_ADDITIONAL}" != "" ]; then
  yq write $DEPLOYMENT_FILE_ADDITIONAL --doc $DEPLOYMENT_DOC_INDEX "spec.template.spec.containers[0].image" "${REGISTRY_URL}/${REGISTRY_NAMESPACE}/${IMAGE_NAME}:${IMAGE_TAG}" > ${NEW_DEPLOYMENT_FILE}
  mv -f ${NEW_DEPLOYMENT_FILE} ${DEPLOYMENT_FILE_ADDITIONAL}
  cat ${DEPLOYMENT_FILE_ADDITIONAL}
fi

git add .
git commit -m "Git Commit:${GIT_COMMIT} App build number: ${BUILD_NUMBER}"
git push origin ${SOURCE_BRANCH_NAME}

MR_ID=$(curl -s --request POST --header "Private-Token: ${GITLAB_ACCESS_TOKEN}" https://${GITLAB_DOMAIN}/api/v4/projects/${GITLAB_OPS_PROJECT_ID}/merge_requests -d "source_branch=${SOURCE_BRANCH_NAME}&target_branch=${TARGET_BRANCH_NAME}&title=update+to+the+latest+docker+image+tag+in+the+manifest+file+for+${REGISTRY_NAMESPACE}+env" | jq -r '.iid')

expr "${MR_ID} + 1" > /dev/null 2>&1
if [ $? -lt 2 ] ; then
  echo "New merge request was successfully created. MR ID is ${MR_ID}."
else
  echo "New merge request was not created. Exit this script."
  exit 1
fi

if [ -z ${DEPLOYMENT_FILE_ADDITIONAL} ];then
  STATE=$(curl -s --request PUT --header "Private-Token: ${GITLAB_ACCESS_TOKEN}" https://${GITLAB_DOMAIN}/api/v4/projects/${GITLAB_OPS_PROJECT_ID}/merge_requests/${MR_ID}/merge?should_remove_source_branch=${REMOVE_SOURCE_BRANCH} | jq -r '.state')
  if [ "${STATE}" = "merged" ];then
    echo "New merge request was successfully merged."
  else
    echo "New merge request was not merged. Exit this script."
    exit 1
  fi
fi
