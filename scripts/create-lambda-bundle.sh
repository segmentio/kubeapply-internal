#!/bin/bash

# Create a bundle for lambda.
#
# Usage:
#   ./scripts/create-lambda-bundle.sh [zip output file name]

set -e

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && cd .. && pwd )"
DEFAULT_OUTPUT_NAME="lambda.zip"
OUTPUT_NAME=${1:-$DEFAULT_OUTPUT_NAME}
OUTPUT_ZIP=${REPO_ROOT}/${OUTPUT_NAME}

echo "Creating bundle at ${OUTPUT_ZIP}"

pushd ${REPO_ROOT}/build
zip -r9 $OUTPUT_ZIP kubeapply-lambda
zip -r9 $OUTPUT_ZIP kubeapply
popd

TEMP_DIR=$(mktemp -d)

function cleanup {
  rm -rf "${TEMP_DIR}"
  echo "Deleted temp working directory ${TEMP_DIR}"
}

trap cleanup EXIT

pushd ${TEMP_DIR}

$REPO_ROOT/scripts/pull-deps.sh

# Check if binaries exist in the current directory, if not try to find them
for bin in helm aws-iam-authenticator kubectl; do
  if [[ -f "${bin}" ]]; then
    # Binary found in current directory
    echo "Adding ${bin} from current directory"
    zip -r9 $OUTPUT_ZIP ${bin}
  elif [[ -f "${HOME}/local/bin/${bin}" ]]; then
    # Binary found in HOME/local/bin
    echo "Adding ${bin} from ${HOME}/local/bin"
    cp "${HOME}/local/bin/${bin}" .
    zip -r9 $OUTPUT_ZIP ${bin}
  else
    echo "Warning: Could not find ${bin} in current directory or ${HOME}/local/bin"
  fi
done

echo "Created bundle ${OUTPUT_ZIP}"

popd
