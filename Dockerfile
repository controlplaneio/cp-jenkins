FROM jenkins/jenkins:lts
# FROM jenkins/jenkins:2.184

ARG FOOTER_URL="https://jenkins.io"
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false -Dhudson.footerURL=${FOOTER_URL} -Djava.util.logging=DEBUG" \
    JENKINS_CONFIG_HOME="/usr/share/jenkins" \
    TRY_UPGRADE_IF_NO_MARKER=true

ENV GOSU_VERSION="1.10" \
    TINI_VERSION="v0.16.1"

RUN echo 2.0 > /usr/share/jenkins/ref/jenkins.install.UpgradeWizard.state

USER root
RUN \
    apt-get update \
    && apt-get install -y \
      apt \
      apt-transport-https \
      bash \
      ca-certificates \
      curl \
      gnupg2 \
      jq \
      make \
      python-pip \
      python3-pip \
      software-properties-common \
    \
    && ARCH="$(dpkg --print-architecture | awk -F- '{ print $NF }')" \
    \
    && curl -fsSL https://download.docker.com/linux/$(. /etc/os-release; echo "$ID")/gpg | apt-key add - \
    && add-apt-repository \
      "deb [arch=${ARCH}] https://download.docker.com/linux/$(. /etc/os-release; echo "$ID") \
      $(lsb_release -cs) \
      stable" \
    && apt-get update \
    && apt-get install -y \
      docker-ce \
    && adduser jenkins users \
    && adduser jenkins docker \
    \
    && wget -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/${GOSU_VERSION}/gosu-${ARCH}" \
    && chmod +x /usr/local/bin/gosu \
    && gosu nobody true \
    \
    && wget -O /usr/local/bin/tini "https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini-${ARCH}" \
    && chmod +x /usr/local/bin/tini

RUN \
  mkdir -p \
    "${JENKINS_HOME}/.ssh/" \
    "${JENKINS_HOME}/config/" \
  || true \
  && chown jenkins:jenkins "${JENKINS_HOME}" -R \
  && ssh-keyscan -H github.com gitlab.com bitbucket.org >> /etc/ssh/ssh_known_hosts

RUN pip3 install ansible && ansible --version && ansible-galaxy install dev-sec.os-hardening && \
 printf -- "- hosts: 127.0.0.1\n  roles:\n    - dev-sec.os-hardening\n  vars:\n    - sysctl_config: []" \
 | tee /tmp/harden &&  ansible-playbook /tmp/harden --skip-tags "packages" \
 && pip3 uninstall --yes --quiet ansible

ARG CACHE_BUSTER=KEEP_CACHE

# install plugins
SHELL ["/bin/bash", "-c"]
COPY plugins-base.txt /usr/share/jenkins/ref/
RUN \
  ATTEMPTS=2 \
  /usr/local/bin/install-plugins.sh < /usr/share/jenkins/ref/plugins-base.txt \
  \
  && [[ ! -f /usr/share/jenkins/ref/plugins/failed-plugins.txt ]]


COPY plugins-extra.txt /usr/share/jenkins/ref/
RUN \
  ATTEMPTS=2 \
  /usr/local/bin/install-plugins.sh < /usr/share/jenkins/ref/plugins-extra.txt \
  \
  && [[ ! -f /usr/share/jenkins/ref/plugins/failed-plugins.txt ]]

#COPY init.groovy.d /usr/share/jenkins/ref/init.groovy.d/
COPY entrypoint.sh /entrypoint.sh

RUN curl -Lo /usr/local/bin/goss \
    https://github.com/aelsabbahy/goss/releases/download/v0.3.7/goss-linux-amd64 \
  && chmod +x /usr/local/bin/goss \
  && goss help

# Ensure system dirs are owned by root and not writable by anybody else.
RUN find /bin /etc /lib /sbin /usr -xdev -type d \
  -exec chown root:root {} \; \
  -exec chmod 0755 {} \;

# Remove dangerous commands
RUN find /bin /etc /lib /sbin /usr -xdev \( \
  -name hexdump -o \
  -name chgrp -o \
  -name chown -o \
  -name ln -o \
  -name od -o \
  -name strings -o \
  -name su \
  -name sudo \
  \) -delete

# Remove init scripts since we do not use them.
RUN rm -fr /etc/init.d /lib/rc /etc/conf.d /etc/inittab /etc/runlevels /etc/rc.conf /etc/logrotate.d

# Remove kernel tunables
RUN rm -fr /etc/sysctl* /etc/modprobe.d /etc/modules /etc/mdev.conf /etc/acpi

# Remove root home dir
RUN rm -fr /root

# Remove fstab
RUN rm -f /etc/fstab

# Remove any symlinks that we broke during previous steps
RUN find /bin /etc /lib /sbin /usr -xdev -type l -exec test ! -e {} \; -delete

# remove apt package manager
RUN find / -type f -iname '*apt*' -xdev -delete
RUN find / -type d -iname '*apt*' -print0 -xdev | xargs -0 rm -rf --

ENV CASC_JENKINS_CONFIG=/casc_config/cp-jenkins-export.yaml
COPY casc_config/ /casc_config/

ENTRYPOINT ["/entrypoint.sh"]
