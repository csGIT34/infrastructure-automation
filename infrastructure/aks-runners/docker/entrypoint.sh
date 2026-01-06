#!/bin/bash

set -e

cleanup() {
        echo "Removing runner..."
        ./config.sh remove --unattended --token ${RUNNER_TOKEN}
}

trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

./config.sh \
        --url https://github.com/${GITHUB_OWNER}/${GITHUB_REPO} \
        --token ${RUNNER_TOKEN} \
        --name "$(hostname)" \
        --labels "${RUNNER_LABELS}" \
        --work _work \
        --unattended \
        --replace

./run.sh & wait $!
