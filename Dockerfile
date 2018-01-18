FROM jenkins/jenkins:2.89.3

ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false -Dhudson.footerURL=https://control-plane.io  -Djava.util.logging=DEBUG" \
    JENKINS_CONFIG_HOME="/usr/share/jenkins" \
    TRY_UPGRADE_IF_NO_MARKER=true

RUN echo 2.0 > /usr/share/jenkins/ref/jenkins.install.UpgradeWizard.state

USER root
RUN \
    apt-get update \
    && apt-get install -y \
      apt \
      make \
      bash \
      python-pip \
      apt-transport-https \
      ca-certificates \
      curl \
      gnupg2 \
      software-properties-common \
    && curl -fsSL https://download.docker.com/linux/$(. /etc/os-release; echo "$ID")/gpg | apt-key add - \
    && add-apt-repository \
      "deb [arch=amd64] https://download.docker.com/linux/$(. /etc/os-release; echo "$ID") \
      $(lsb_release -cs) \
      stable" \
    && apt-get update \
    && apt-get install -y \
      docker-ce \
    && adduser jenkins users \
    && adduser jenkins docker

COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN \
  /usr/local/bin/install-plugins.sh < /usr/share/jenkins/ref/plugins.txt

COPY init.groovy.d /usr/share/jenkins/ref/init.groovy.d/

COPY known_hosts /opt/known_hosts
RUN \
  mkdir -p "${JENKINS_HOME}/.ssh/" \
  && cp /opt/known_hosts "${JENKINS_HOME}/.ssh/" \
  && chown jenkins:jenkins "${JENKINS_HOME}" -R

ARG GOSU_VERSION=1.10
RUN \
  dpkgArch="$(dpkg --print-architecture | awk -F- '{ print $NF }')" \
  && wget -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch" \
 && chmod +x /usr/local/bin/gosu \
 && gosu nobody true

ENV TINI_VERSION v0.16.1
ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini /bin/tini
RUN chmod +x /bin/tini

COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
