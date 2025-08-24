# Argo CD (Helm) — Continuous Delivery setup

Installs **Argo CD** via the official Helm chart, registers your **GitLab** repo (HTTPS + PAT),
and creates the **Application** `final-project-app` (branch `main`, path `k8s`) to deploy into
namespace `final-project`. Argo CD UI is exposed as **NodePort 30454**.

## Usage
```bash
cd cd/argocd
./deploy.sh
```

> The GitLab PAT is read from `cd/argocd/.env`. **Do not commit** that file.
