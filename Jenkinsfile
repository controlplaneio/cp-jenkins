#!/usr/bin/env groovy

def getContainerTag() {
  if (env.GIT_COMMIT == "") {
    error "GIT_COMMIT value was empty at usage. "
  }
  return "${env.BUILD_ID}-${env.GIT_COMMIT}"
}

pipeline {
  agent none

  post {
    failure {
      emailext (
          subject: "cp-infra build failed:  '${env.BUILD_NUMBER}'",
          body: "${currentBuild.rawBuild.getLog(100).join("\n")}",
          to: "team@control-plane.io",
          from: "jenkins@control-plane.io"
          )
    }
  }

  environment {
    ENVIRONMENT = 'ops'
  }

  stages {
    stage('Test') {
      agent {
        docker {
          image 'docker.io/controlplane/gcloud-sdk:latest'
          args '-v /var/run/docker.sock:/var/run/docker.sock ' +
            '--user=root ' +
            '--cap-drop=ALL ' +
            '--cap-add=DAC_OVERRIDE'
        }
      }

      options {
        timeout(time: 15, unit: 'MINUTES')
        retry(1)
        timestamps()
      }

      steps {
        ansiColor('xterm') {
          sh 'make pull-base-image || make pull-base-image'
          sh "make test CONTAINER_TAG='${getContainerTag()}' CACHE_BUSTER='${env.CACHE_BUSTER}'"
        }
      }
    }

    stage('Push') {
      when {
        branch "master"
      }
      agent {
        docker {
          image 'docker.io/controlplane/gcloud-sdk:latest'
          args '-v /var/run/docker.sock:/var/run/docker.sock ' +
            '--user=root ' +
            '--cap-drop=ALL ' +
            '--cap-add=DAC_OVERRIDE'
        }
      }

      environment {
        DOCKER_REGISTRY_CREDENTIALS = credentials("${ENVIRONMENT}_docker_credentials")
      }

      options {
        timeout(time: 15, unit: 'MINUTES')
        retry(1)
        timestamps()
      }

      steps {
        ansiColor('xterm') {
          sh """
            echo '${DOCKER_REGISTRY_CREDENTIALS_PSW}' \
            | docker login \
              --username '${DOCKER_REGISTRY_CREDENTIALS_USR}' \
              --password-stdin

            make push \
              CONTAINER_TAG="${getContainerTag()}"
          """
        }
      }
    }
  }
}
