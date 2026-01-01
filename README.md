# GitHub Account Mirroring & Backup

This repository contains a GitHub Action workflow that automatically mirrors your entire GitHub account (all repositories, branches, tags) to:
1.  **GitLab**: For hot failover/mirroring.
2.  **AWS S3**: For cold storage/archival (as bare git repositories).

The workflow runs daily at midnight (`0 0 * * *`) or can be triggered manually.

## Features

-   **Comprehensive Backup:** Backs up all public and private repositories of the authenticated user.
-   **Incremental:** Uses efficient git fetching and S3 sync to only upload changes.
-   **Secure:** All credentials are stored in GitHub Secrets.
-   **Automated:** "Set-and-forget" daily schedule.

## Prerequisites & Configuration

To use this backup system, you must configure the following **Secrets** and **Variables** in this repository's settings.

### 1. GitHub Secrets
Go to `Settings` -> `Secrets and variables` -> `Actions` -> `Secrets` -> `New repository secret`.

| Secret Name | Description |
| :--- | :--- |
| `GH_TOKEN` | GitHub Personal Access Token. Scopes: `repo` (full control), `read:org`. |
| `GITLAB_TOKEN` | GitLab Personal Access Token. Scopes: `api`, `write_repository`. |
| `AWS_ACCESS_KEY_ID` | AWS Access Key ID with `s3:ListBucket`, `s3:PutObject`, `s3:DeleteObject` permissions for the bucket. |
| `AWS_SECRET_ACCESS_KEY` | AWS Secret Access Key. |

### 2. GitHub Variables
Go to `Settings` -> `Secrets and variables` -> `Actions` -> `Variables` -> `New repository variable`.

| Variable Name | Description |
| :--- | :--- |
| `GITLAB_USER_OR_GROUP` | The GitLab username or group/namespace where repositories should be mirrored (e.g., `my-backup-group`). |
| `S3_BUCKET_NAME` | The name of the AWS S3 bucket to sync to (e.g., `my-github-backup-vault`). |

### 3. AWS S3 Setup
Ensure your S3 bucket exists and is private. The `AWS_ACCESS_KEY_ID` user must have permissions to write to this bucket.

## Architecture

1.  **Workflow Trigger:** Daily cron or manual dispatch.
2.  **Environment:** Runs on `ubuntu-latest`.
3.  **Tooling:** Uses [Gickup](https://github.com/cooperspencer/gickup) to clone/mirror repositories.
4.  **Process:**
    *   Authenticates with GitHub using `GH_TOKEN`.
    *   Detects the GitHub username.
    *   Mirrors all repositories to the specified GitLab namespace.
    *   Mirrors all repositories to a local directory.
    *   Syncs the local directory to the S3 bucket using `aws s3 sync`.

## Verification

-   **GitLab:** Check your GitLab group. You should see all your GitHub repositories mirrored there.
-   **S3:** Browse your S3 bucket. You should see folders like `repo-name.git` containing the raw git data.

## Restoration

To restore a repository from S3:
```bash
aws s3 sync s3://your-bucket-name/repo-name.git local-repo.git
git clone local-repo.git restored-repo
```
