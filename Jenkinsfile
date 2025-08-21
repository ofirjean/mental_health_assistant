pipeline {
  agent any
  options { timestamps(); ansiColor('xterm') }
  environment {
    DOCKER_REPO = 'ofirjean/mental-health-assistant'
    CHART_PATH  = 'app/helm'
    VALUES_FILE = 'app/helm/values-prod.yaml'
  }
  stages {
    stage('Checkout') { steps { checkout scm } }
    stage('Set Tag') {
      steps {
        script {
          env.TAG = "v0.1.${env.BUILD_NUMBER}"
          echo "Using image tag: ${env.TAG}"
        }
      }
    }
    stage('Build & Push Image') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'dockerhub', usernameVariable: 'DH_USER', passwordVariable: 'DH_PASS')]) {
          sh '''
            echo "$DH_PASS" | docker login -u "$DH_USER" --password-stdin
            docker build -t $DOCKER_REPO:$TAG app
            docker push $DOCKER_REPO:$TAG
          '''
        }
      }
    }
    stage('Bump Helm image.tag') {
      steps {
        sh '''
          sed -i -E "s#^(\\s*tag:\\s*).+#\\1$TAG#" "$VALUES_FILE"
          echo "New tag in $VALUES_FILE:"
          grep -n "tag:" "$VALUES_FILE"
        '''
      }
    }
    stage('Commit & Push') {
      when { branch 'main' }
      steps {
        sshagent(credentials: ['github-ssh']) {
          sh '''
            mkdir -p ~/.ssh && ssh-keyscan github.com >> ~/.ssh/known_hosts 2>/dev/null || true
            git config user.name "Jenkins CI"
            git config user.email "ci@local"
            git add "$VALUES_FILE"
            git commit -m "ci: bump image tag to $TAG" || echo "Nothing to commit"
            BRANCH=$(git rev-parse --abbrev-ref HEAD)
            git push origin "HEAD:$BRANCH"
          '''
        }
      }
    }
  }
  post { always { echo "Done. Tag=${env.TAG}" } }
}
