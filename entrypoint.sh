#!/bin/bash

set -euxo pipefail

if [ -S /var/run/docker.sock ]; then
  # get gid of docker socket file
  DOCKER_SOCK_GID=$(ls -ng /var/run/docker.sock | cut -f3 -d' ')

  # get group of docker inside container
  DOCKER_GID=$(getent group docker | cut -f3 -d: || true)

  # if they don't match, adjust
  if [[ ! -z "${DOCKER_SOCK_GID}" && "${DOCKER_SOCK_GID}" != "${DOCKER_GID}" ]]; then
    groupmod -g "${DOCKER_SOCK_GID}" docker
  fi

  if ! groups jenkins | grep -q docker; then
    usermod -aG docker jenkins
  fi
fi


sed -E '1s,(.*)[[:space:]]*$,\1x,g' -i /usr/local/bin/jenkins.sh

# drop access to jenkins user and run jenkins entrypoint
exec gosu jenkins /usr/local/bin/tini -- /usr/local/bin/jenkins.sh "$@"
