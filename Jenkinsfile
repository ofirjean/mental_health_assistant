pipeline {
  agent any

  options {
    timestamps()
    ansiColor('xterm')
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '20'))
  }

  // Poll SCM every 2 minutes
  triggers {
    pollSCM('*/2 * * * *')   // use 'H/2 * * * *' if you prefer hashed spreading
  }

  parameters {
    string(name: 'FORCE_TAG', defaultValue: '', description: 'Override image tag; leave empty to auto-generate on main')
  }

  environment {
    DOCKER_REPO     = 'ofirjean/mental-health-assistant'
    VALUES_FILE     = 'app/helm/values-prod.yaml'
    CRED_DOCKERHUB  = 'DockerHub'   // matches your screenshot
    CRED_GITHUB_PAT = 'github-pat'  // username = GitHub user, password = PAT
    CRED_GITLAB_PAT = 'gitlab-pat'  // username = GitLab user, password = PAT
  }

  stages {
    stage('Checkout'){
      steps {
        checkout scm
        sh '''
          git config --global --add safe.directory "$PWD"
          git status -sb || true
        '''
      }
    }

    stage('Set Tag'){
      when { branch 'main' }
      steps {
        script {
          env.TAG = params.FORCE_TAG?.trim() ? params.FORCE_TAG.trim() : "v0.1.${env.BUILD_NUMBER}"
        }
        echo "Using TAG=${env.TAG}"
      }
    }

    stage('Build & Push Image'){
      when { branch 'main' }
      steps {
        withCredentials([usernamePassword(credentialsId: env.CRED_DOCKERHUB, usernameVariable: 'DH_USER', passwordVariable: 'DH_PASS')]) {
          sh '''
            set -euo pipefail
            echo "$DH_PASS" | docker login -u "$DH_USER" --password-stdin
            docker build -t "$DOCKER_REPO:$TAG" app
            docker push  "$DOCKER_REPO:$TAG"
            docker logout || true
          '''
        }
      }
    }

    stage('Bump Helm image.tag'){
      when { branch 'main' }
      steps {
        sh '''
          set -euo pipefail
          if command -v yq >/dev/null 2>&1; then
            yq -i '.image.tag = env(TAG)' "$VALUES_FILE"
          else
            # portable awk update inside the nearest top-level "image:" block
            awk -v tag="$TAG" '
              BEGIN{in_image=0}
              /^[[:space:]]*image:[[:space:]]*$/ {in_image=1; print; next}
              /^[^[:space:]]/ {in_image=0}
              in_image && /^[[:space:]]*tag:[[:space:]]*/ { sub(/tag:.*/, "tag: " tag); print; next }
              {print}
            ' "$VALUES_FILE" > "$VALUES_FILE.tmp" && mv "$VALUES_FILE.tmp" "$VALUES_FILE"
          fi
          echo "==== values snippet ===="
          grep -nE '^[[:space:]]*image:|^[[:space:]]*tag:' "$VALUES_FILE" | sed -n '1,120p'
        '''
      }
    }

    stage('Commit & Push to GitHub (PAT)'){
      when { branch 'main' }
      steps {
        withCredentials([usernamePassword(credentialsId: env.CRED_GITHUB_PAT, usernameVariable: 'GH_USER', passwordVariable: 'GH_PAT')]) {
          sh '''
            set -euo pipefail
            git config user.name  "Jenkins CI"
            git config user.email "ci@local"
            git add "$VALUES_FILE"
            git commit -m "ci: bump image tag to $TAG" || true

            # Use PAT as password via https remote
            git remote set-url origin "https://${GH_USER}:${GH_PAT}@github.com/ofirjean/mental_health_assistant.git"

            BRANCH="$(git rev-parse --abbrev-ref HEAD)"
            git push origin "HEAD:${BRANCH}"

            # Optional traceability tag
            git tag -f "$TAG" || true
            git push origin --force "refs/tags/$TAG"
          '''
        }
      }
    }

    stage('Mirror to GitLab (PAT)'){
      when { branch 'main' }
      steps {
        withCredentials([usernamePassword(credentialsId: env.CRED_GITLAB_PAT, usernameVariable: 'GL_USER', passwordVariable: 'GL_PAT')]) {
          sh '''
            set -euo pipefail
            git remote remove gitlab 2>/dev/null || true
            git remote add    gitlab "https://${GL_USER}:${GL_PAT}@gitlab.com/sela-tracks/1116/students/ofir/final-project.git"
            BRANCH="$(git rev-parse --abbrev-ref HEAD)"
            git push gitlab "HEAD:${BRANCH}"
            git push gitlab "refs/tags/$TAG"
          '''
        }
      }
    }
  }

  post {
    success { echo "Built & pushed ${env.DOCKER_REPO}:${env.TAG}" }
    failure { echo "Build failed on branch ${env.BRANCH_NAME ?: 'n/a'}." }
    always  { cleanWs deleteDirs: true, notFailBuild: true }
  }
}
