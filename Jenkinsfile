pipeline {
  agent none

  stages {
    stage('Test') {
      agent {
        docker { image 'docker.io/controlplane/gcloud-sdk:latest' }
      }

      steps {
        ansiColor('xterm') {
          sh 'make test'
        }
      }
    }
  }
}
