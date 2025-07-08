#!/bin/bash

set -e

if [ -z "$1" ]; then
  echo "Usage: ./buildpush.sh stage|prod"
  exit
fi

if [ $1 != "stage" -a $1 != "prod" ]; then
  echo "Usage: ./buildpush.sh stage|prod"
  exit
fi

ENV=$1
UPLOADER_ROLE="arn:aws:iam::752180062774:role/kubeapply-uploader"
if [ $1 != "prod" ]; then
  UPLOADER_ROLE="arn:aws:iam::355207333203:role/kubeapply-uploader"
fi

KUBEAPPLY_LAMBDA_SCRIPT_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

cd $GOPATH/src/github.com/segmentio/kubeapply

aws-okta exec $ENV-write -- cloud-toolbox assume-roles $UPLOADER_ROLE -- imager buildpush . -f Dockerfile.lambda -d all-${ENV} \
--build-arg VERSION_REF=`git describe --tags --always --dirty="-dev"` \
--destination-aliases $KUBEAPPLY_LAMBDA_SCRIPT_ROOT/regions.yaml \
--repository kubeapply-lambda --local