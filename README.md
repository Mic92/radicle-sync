# Mirror to Radicle

A GitHub Action that mirrors your code to the Radicle peer-to-peer code hosting network.

## Features

- Works on `ubuntu-slim` runners (no apt-get required)
- Supports custom preferred seeds
- Simple setup with GitHub secrets
- Automatically creates PRs for contributions made to Radicle
- Fast execution with GitHub Actions cache (only slow on first run)

## Usage

```yaml
name: Mirror to Radicle

on:
  push:
    branches:
      - main
  workflow_dispatch:

jobs:
  mirror:
    runs-on: ubuntu-latest
    environment: radicle
    permissions:
      contents: write
      pull-requests: write
    steps:
      - id: mirror
        uses: Mic92/mirror-to-radicle@main
        with:
          radicle-identity-alias: "${{ secrets.RADICLE_IDENTITY_ALIAS }}"
          radicle-identity-passphrase: "${{ secrets.RADICLE_IDENTITY_PASSPHRASE }}"
          radicle-identity-private-key: "${{ secrets.RADICLE_IDENTITY_PRIVATE_KEY }}"
          radicle-identity-public-key: "${{ secrets.RADICLE_IDENTITY_PUBLIC_KEY }}"
          radicle-project-name: "${{ secrets.RADICLE_PROJECT_NAME }}"
          radicle-repository-id: "${{ secrets.RADICLE_REPOSITORY_ID }}"
          preferred-seeds: "z6MktZckvzz29eJtUQ4u9bkNu8jihg1sRvknUZMm1xq2stn9@radicle.thalheim.io:8776"
```

**Note**: The workflow requires `contents: write` permission to push branches and `pull-requests: write` to create PRs when Radicle has contributions.

**Tip**: By default, PRs created by `GITHUB_TOKEN` don't trigger workflows. To trigger workflows on sync PRs, use a GitHub App token:

```yaml
- name: Generate GitHub App Token
  id: app-token
  uses: actions/create-github-app-token@v2
  with:
    app-id: ${{ secrets.APP_ID }}
    private-key: ${{ secrets.APP_PRIVATE_KEY }}

- uses: Mic92/mirror-to-radicle@main
  with:
    github-token: ${{ steps.app-token.outputs.token }}
    # ... other inputs
```

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `radicle-identity-alias` | Alias for your Radicle identity | Yes | |
| `radicle-identity-passphrase` | Passphrase for the identity (base64 encoded) | Yes | |
| `radicle-identity-private-key` | Private key (base64 encoded) | Yes | |
| `radicle-identity-public-key` | Public key (base64 encoded) | Yes | |
| `radicle-repository-id` | Repository ID (rad:xxx) | Yes | |
| `radicle-project-name` | Project name | Yes | |
| `preferred-seeds` | Comma-separated list of preferred seeds | No | |
| `git-user-name` | Git user name for merge commits | No | `Radicle Mirror Bot` |
| `git-user-email` | Git user email for merge commits | No | `radicle-mirror@users.noreply.github.com` |
| `pr-labels` | Comma-separated list of labels for PRs | No | |
| `github-token` | GitHub token for authentication | No | `${{ github.token }}` |

## How it Works

This action mirrors your GitHub repository to the Radicle network:

1. **First run**: Clones the repository from Radicle's P2P network (may take 30-180 seconds) and caches the Radicle storage
2. **Subsequent runs**: Restores Radicle storage from cache and syncs updates (fast, typically <30 seconds)
3. **Normal operation**: Pushes changes from GitHub to Radicle
4. **Radicle contributions**: If the action detects commits in Radicle that aren't in GitHub, it:
   - Creates/updates a pull request branch `radicle-sync/<branch-name>`
   - The PR allows you to review and merge Radicle contributions through GitHub's standard workflow
   - If there are merge conflicts, the action fails and requires manual intervention

This ensures that contributions made directly to Radicle are preserved and properly reviewed.

## Setup

See [gh-radicle](https://github.com/Mic92/dotfiles/tree/main/pkgs/gh-radicle) for a tool that automates the setup of GitHub secrets and workflow files.
