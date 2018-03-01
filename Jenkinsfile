pipeline {
  agent none

  environment {
  }

  stages {
    stage('Test') {
      agent {
        docker { image 'docker.io/controlplane/gcloud-sdk:latest' }
      }

      environment {
      }

      steps {
        ansiColor('xterm') {
          sh 'make test'
        }
      }
    }
  }
}
