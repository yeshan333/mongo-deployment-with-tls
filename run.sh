#!/bin/bash

ROOT=$(pwd)

kill_if_file_exists() {
  if [ -f $1 ]; then
    kill -9 $(cat $1)
    rm -f $1
  fi
}

prepare_environment() {
  if ! [ -x "$(command -v go)" ]; then
    echo "Error: go is not installed."
    exit 1
  fi
  if ! [ -x "$(command -v mkcert)" ]; then
    echo "Error: mkcert is not installed."
    go install filippo.io/mkcert@master
    exit 1
  fi
}

setup_deployment() {
  source $ROOT/deployments/$1/launch.sh
  cd $ROOT/deployments/$1
  ROOT=$ROOT CURRENT_DEPLOYMENT=$1 launch
}

# split muti deploy by comma
IFS=',' read -ra SPECIFIC_DEPLOYMENTS <<< "$1"
EXTRA_ARGS=("${@:2}")

SPECIFIC_DEPLOYMENT_COUNT=${#SPECIFIC_DEPLOYMENTS[@]}

if [ $SPECIFIC_DEPLOYMENT_COUNT -eq 0 ] || [[ " ${SPECIFIC_DEPLOYMENTS[@]} " =~ "all" ]];then
  tmp=`ls $ROOT/deployments`
  echo "if not specify deployment, will startup all deployments"
  for var in $tmp
  do
    TARGET_DEPLOYMENTS+=("$var")
  done
else
  TARGET_DEPLOYMENTS=( "${SPECIFIC_DEPLOYMENTS[@]}" )
fi

DEPLOTMENTS_COUNT=${#TARGET_DEPLOYMENTS[@]}
echo "specific $DEPLOTMENTS_COUNT deployments: ${TARGET_DEPLOYMENTS[@]}"
prepare_environment
for deployment in ${TARGET_DEPLOYMENTS[@]}
do
  setup_deployment $deployment
  run_test
  # clean_up $deployment
done