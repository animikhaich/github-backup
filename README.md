# GitHub Account Mirroring & Backup

This repository contains a GitHub Action workflow that automatically mirrors your entire GitHub account (all repositories, branches, tags) to:
1.  **GitLab**: For active mirroring.
2.  **AWS S3**: For cold storage/archival (both as bare git repositories and as extracted source code).

The workflow runs daily at midnight UTC (`0 0 */2 * *` in GitHub Actions) or can be triggered manually.

## Features

-   **Comprehensive Backup:** Backs up all public and private repositories of the authenticated user.
-   **Dual S3 Storage:**
    -   **Full History:** Stores bare git repositories in `s3://bucket/git/`.
    -   **Source Snapshot:** Stores the latest source code (files only) in `s3://bucket/source/` for easy browsing.
-   **Incremental:** Uses efficient git fetching and S3 sync to only upload changes.
-   **Secure:** All credentials are stored in GitHub Secrets.
-   **High Performance:** Uses parallel processing to extract source code and upload to S3 concurrently.
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
| `AWS_REGION` | (Optional) The AWS region where your S3 bucket is located (e.g., `us-east-1`, `eu-west-1`). Defaults to `us-east-1` if not set. |

### 3. AWS S3 Setup
Ensure your S3 bucket exists, is private, and that its region matches the value you configure in `AWS_REGION` (the example workflow defaults to `us-east-1`). The `AWS_ACCESS_KEY_ID` user must have permissions to write to this bucket.

## Architecture

1.  **Workflow Trigger:** Scheduled cron job (every 2 days) or manual dispatch.
2.  **Environment:** Runs on `ubuntu-latest`.
3.  **Tooling:**
    -   **Gickup**: Mirrors repositories from GitHub to GitLab and a local staging directory.
    -   **Custom Script**: `.github/scripts/s3_upload.sh` handles the S3 upload logic.
4.  **Process:**
    *   Authenticates with GitHub using `GH_TOKEN`.
    *   Detects the GitHub username.
    *   Mirrors all repositories to the specified GitLab namespace.
    *   Mirrors all repositories to a local directory (bare format).
    *   **Parallel S3 Sync & Extraction:**
        *   Uploads the bare git repositories to `s3://bucket/git/`.
        *   Concurrently extracts the source code (shallow clone) from the local backups.
        *   Uploads the extracted source code to `s3://bucket/source/`.

## Verification

-   **GitLab:** Check your GitLab group. You should see all your GitHub repositories mirrored there.
-   **S3:** Browse your S3 bucket. You should see two main folders:
    -   `git/`: Contains the bare git repositories (e.g., `repo-name.git`).
    -   `source/`: Contains the readable source code folders (e.g., `repo-name`).
        *   **Note:** Git LFS files (large binaries) are skipped during extraction to save space and avoid errors. They are stored as pointer files in the `source/` directory.

## Restoration

You have two options for restoring from S3:

### Option 1: Quick File Access (Source Code)
If you just need to read a file or get the latest version of the code without git history:
```bash
# Download the specific file or directory
aws s3 cp s3://your-bucket-name/source/repo-name/path/to/file .
# OR sync the whole repo source
aws s3 sync s3://your-bucket-name/source/repo-name ./repo-name
```

### Option 2: Full Repository Restoration (Git History)
To restore the full repository with all history, branches, and tags:
```bash
# Sync the bare repository from S3
aws s3 sync s3://your-bucket-name/git/repo-name.git local-repo.git

# Clone from the local bare repository
git clone local-repo.git restored-repo

# OR create a mirror clone to preserve all refs
git clone --mirror local-repo.git restored-repo-mirror.git
```
