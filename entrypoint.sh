#!/bin/bash

set -euxo pipefail

# get gid of docker socket file
DOCKER_SOCK_GID=$(ls -ng "/var/run/docker.sock" | cut -f3 -d' ')

# get group of docker inside container
DOCKER_GID=$(getent group "docker" | cut -f3 -d: || true)

# if they don't match, adjust
if [[ -n "${DOCKER_SOCK_GID}" && "${DOCKER_SOCK_GID}" != "${DOCKER_GID}" ]]; then
  groupmod -g "${DOCKER_SOCK_GID}" docker
fi

if ! groups "jenkins" | grep -q "docker"; then
  usermod -aG "docker" "jenkins"
fi


# drop access to jenkins user and run jenkins master or inbound-ageny entrypoint
if [[ -x /usr/local/bin/jenkins-agent ]]; then
  exec /usr/local/bin/jenkins-agent "$@"
else
  sed -E '1s,(.*)[[:space:]]*$,\1x,g' -i "/usr/local/bin/jenkins.sh"
  exec gosu jenkins /usr/local/bin/tini -- /usr/local/bin/jenkins.sh "$@"
fi
