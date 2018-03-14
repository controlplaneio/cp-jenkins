FROM jenkins/jenkins:lts

ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false -Dhudson.footerURL=https://jenkins.ops.ctlplane.io  -Djava.util.logging=DEBUG" \
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

COPY known_hosts /opt/known_hosts
RUN \
  mkdir -p "${JENKINS_HOME}/.ssh/" || true \
  && ssh-keyscan -H github.com >> "${JENKINS_HOME}/.ssh/known_hosts" \
  && chown jenkins:jenkins "${JENKINS_HOME}" -R

COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN \
  /usr/local/bin/install-plugins.sh < /usr/share/jenkins/ref/plugins.txt

COPY plugins-test.txt /usr/share/jenkins/ref/plugins-test.txt
RUN \
  /usr/local/bin/install-plugins.sh < /usr/share/jenkins/ref/plugins-test.txt

COPY init.groovy.d /usr/share/jenkins/ref/init.groovy.d/
COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
