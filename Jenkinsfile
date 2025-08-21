pipeline {
  agent any
  options { timestamps(); ansiColor('xterm') }
  environment {
    DOCKER_REPO       = 'ofirjean/mental-health-assistant'
    VALUES_FILE       = 'app/helm/values-prod.yaml'
    CRED_DOCKERHUB    = 'dockerhub'
    CRED_GITHUB_PAT   = 'github-pat'
    CRED_GITLAB_PAT   = 'gitlab-pat'
  }
  stages {
    stage('Checkout'){ steps { checkout scm; sh 'git config --global --add safe.directory "$PWD"' } }
    stage('Set Tag'){ when { branch 'main' } steps { script { env.TAG = "v0.1.${env.BUILD_NUMBER}" } } }
    stage('Build & Push Image'){
      when { branch 'main' }
      steps {
        withCredentials([usernamePassword(credentialsId: env.CRED_DOCKERHUB, usernameVariable: 'DH_USER', passwordVariable: 'DH_PASS')]) {
          sh '''
            echo "$DH_PASS" | docker login -u "$DH_USER" --password-stdin
            docker build -t $DOCKER_REPO:$TAG app
            docker push  $DOCKER_REPO:$TAG
          '''
        }
      }
    }
    stage('Bump Helm image.tag'){
      when { branch 'main' }
      steps {
        sh '''
          sed -i -E "s#^(\\s*tag:\\s*).+#\\1$TAG#" "$VALUES_FILE"
          grep -n "tag:" "$VALUES_FILE"
        '''
      }
    }
    stage('Commit & Push to GitHub (PAT)'){
      when { branch 'main' }
      steps {
        withCredentials([usernamePassword(credentialsId: env.CRED_GITHUB_PAT, usernameVariable: 'GH_USER', passwordVariable: 'GH_PAT')]) {
          sh '''
            git config user.name "Jenkins CI"
            git config user.email "ci@local"
            git remote set-url origin "https://${GH_USER}:${GH_PAT}@github.com/ofirjean/mental_health_assistant.git"
            git add "$VALUES_FILE"
            git commit -m "ci: bump image tag to $TAG" || true
            BRANCH=$(git rev-parse --abbrev-ref HEAD)
            git push origin "HEAD:${BRANCH}"
          '''
        }
      }
    }
    stage('Mirror to GitLab (PAT)'){
      when { branch 'main' }
      steps {
        withCredentials([usernamePassword(credentialsId: env.CRED_GITLAB_PAT, usernameVariable: 'GL_USER', passwordVariable: 'GL_PAT')]) {
          sh '''
            git remote remove gitlab 2>/dev/null || true
            git remote add gitlab "https://${GL_USER}:${GL_PAT}@gitlab.com/sela-tracks/1116/students/ofir/final-project.git"
            BRANCH=$(git rev-parse --abbrev-ref HEAD)
            git push gitlab "HEAD:${BRANCH}"
            git push gitlab --tags
          '''
        }
      }
    }
  }
  post { always { echo "Built & pushed ${env.DOCKER_REPO}:${env.TAG ?: 'N/A'}" } }
}
