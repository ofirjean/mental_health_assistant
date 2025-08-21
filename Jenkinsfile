pipeline {
  agent any

  options {
    timestamps()
    ansiColor('xterm')
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '20'))
    overrideIndexTriggers(true) // allow triggers{} in multibranch
  }

  // Poll SCM every ~2 minutes (works in Multibranch thanks to overrideIndexTriggers)
  triggers {
    pollSCM('H/2 * * * *')
  }

  parameters {
    string(name: 'FORCE_TAG', defaultValue: '', description: 'Override image tag; leave empty to auto-generate on main')
  }

  environment {
    DOCKER_REPO     = 'ofirjean/mental-health-assistant'
    VALUES_FILE     = 'app/helm/values-prod.yaml'
    CRED_DOCKERHUB  = 'DockerHub'   // Jenkins cred ID (Username + token)
    CRED_GITHUB_PAT = 'github-pat'  // Username + PAT
    CRED_GITLAB_PAT = 'gitlab-pat'  // Username + PAT
  }

  stages {
    stage('Checkout'){
      steps {
        checkout scm
        sh '''#!/usr/bin/env bash
          set -euo pipefail
          git config --global --add safe.directory "$PWD"
          git status -sb || true
        '''
      }
    }

    stage('Sanity checks') {
      steps {
        sh '''#!/usr/bin/env bash
          set -euo pipefail
          echo "Branch: ${BRANCH_NAME}"
          echo "Workspace: $PWD"
          ls -la

          # Docker availability
          command -v docker || true
          docker version || { echo "Docker not available on this agent"; exit 2; }

          # Ensure values file exists
          test -f "$VALUES_FILE" || { echo "Missing $VALUES_FILE"; exit 3; }

          # Git details
          git --version
          git remote -v
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
        echo "Using Docker Hub credential ID: ${CRED_DOCKERHUB}"
        withCredentials([usernamePassword(credentialsId: env.CRED_DOCKERHUB, usernameVariable: 'DH_USER', passwordVariable: 'DH_PASS')]) {
          sh '''#!/usr/bin/env bash
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
        sh '''#!/usr/bin/env bash
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
          sh '''#!/usr/bin/env bash
            set -euo pipefail
            git config user.name  "Jenkins CI"
            git config user.email "ci@local"
            git add "$VALUES_FILE"
            git commit -m "ci: bump image tag to $TAG" || true

            # Push to GitHub using PAT as password
            git remote set-url origin "https://${GH_USER}:${GH_PAT}@github.com/ofirjean/mental_health_assistant.git"
            BRANCH="${BRANCH_NAME}"
            git push origin "HEAD:${BRANCH}"

            # Optional: tag for traceability
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
          sh '''#!/usr/bin/env bash
            set -euo pipefail
            git remote remove gitlab 2>/dev/null || true
            git remote add    gitlab "https://${GL_USER}:${GL_PAT}@gitlab.com/sela-tracks/1116/students/ofir/final-project.git"
            BRANCH="${BRANCH_NAME}"
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
