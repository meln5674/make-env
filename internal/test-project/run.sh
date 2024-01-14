#!/bin/bash -xeu

SCRIPTPATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

rm -rf "${SCRIPTPATH}/bin/"

(
    set -xeu
    cd "${SCRIPTPATH}/../../" ;
    go run "${SCRIPTPATH}/../../" -C ./internal/test-project;
)

cat -n "${SCRIPTPATH}/make-env.Makefile"

make -C "${SCRIPTPATH}" test-tools k8s-tools

(
    set -xeu
    cd "${SCRIPTPATH}" ;
    bin/ginkgo version ;
    bin/kubectl version --client ;
    bin/helm version ;
)
