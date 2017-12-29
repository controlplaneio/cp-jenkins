FROM jenkins/jenkins:lts

ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false -Dhudson.footerURL=https://control-plane.io" \
    JENKINS_CONFIG_HOME="/usr/share/jenkins"


USER root
RUN apt-get update && apt-get install -y \
  apt \
  make \
  bash \
  docker \
  python-pip

RUN groupadd docker &&\
    adduser jenkins users &&\
    adduser jenkins docker &&\
    pip install jenkins-job-builder &&\
    mkdir -p /etc/jenkins_jobs

USER jenkins

COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
ENV TRY_UPGRADE_IF_NO_MARKER=true
RUN /usr/local/bin/install-plugins.sh < /usr/share/jenkins/ref/plugins.txt \
  || true

COPY init.groovy.d /usr/share/jenkins/ref/init.groovy.d/
COPY setup.yml /usr/share/jenkins/setup.yml

RUN ls -lasp /usr/share/jenkins/ref/init.groovy.d/

RUN echo 2.0 > /usr/share/jenkins/ref/jenkins.install.UpgradeWizard.state

