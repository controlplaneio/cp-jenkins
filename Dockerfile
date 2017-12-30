FROM jenkins/jenkins:lts

ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false -Dhudson.footerURL=https://control-plane.io" \
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
      docker \
      python-pip \
    \
    && groupadd docker \
    && adduser jenkins users \
    && adduser jenkins docker

USER jenkins

COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN \
  /usr/local/bin/install-plugins.sh < /usr/share/jenkins/ref/plugins.txt

COPY init.groovy.d /usr/share/jenkins/ref/init.groovy.d/


