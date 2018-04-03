pipeline {
  agent none

  environment {
    CONTAINER_TAG = 'latest'
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
        disableConcurrentBuilds()
      }

      steps {
        ansiColor('xterm') {
          sh 'make pull-base-image'
          sh 'make test CONTAINER_TAG="${CONTAINER_TAG}"'
        }
      }
    }
  }
}
