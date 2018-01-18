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

# entrypoint is used to update docker gid and revert back to jenkins user
COPY known_hosts /root/.ssh/known_hosts

COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
