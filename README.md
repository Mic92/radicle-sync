# Radicle Sync

> [!WARNING]
> **This repository is deprecated.**
>
> As it turns out radicle's protocol,
> doesn't play nicely together with
> short-lived github actions, leading to the
> repositories updates not beeing visible to
> rest of the network.

A GitHub Action that bidirectionally syncs your code with the [Radicle](https://radicle.xyz) peer-to-peer code hosting network.

## Features

- Supports custom preferred seeds
- Simple setup with GitHub secrets
- Automatically creates PRs for contributions made to Radicle
- Fast execution with GitHub Actions cache (only slow on first run)

## Usage

```yaml
name: Radicle Sync

on:
  push:
    branches:
      - main
  schedule:
    # Run daily to check for Radicle contributions
    - cron: '0 3 * * *'
  workflow_dispatch:

jobs:
  mirror:
    runs-on: ubuntu-latest
    environment: radicle
    permissions:
      contents: write
      pull-requests: write
    steps:
      - uses: Mic92/radicle-sync@main
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

**Optional - Trigger Workflows on PRs**: By default, PRs created by `GITHUB_TOKEN` don't trigger workflows. To enable this, use a GitHub App token:

```yaml
steps:
  - name: Generate GitHub App Token
    id: app-token
    uses: actions/create-github-app-token@v2
    with:
      app-id: ${{ secrets.APP_ID }}
      private-key: ${{ secrets.APP_PRIVATE_KEY }}

  - uses: Mic92/radicle-sync@main
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
| `preferred-seeds` | Comma-separated list of preferred seeds (recommended) | No | |
| `git-user-name` | Git user name for merge commits | No | `Radicle Mirror Bot` |
| `git-user-email` | Git user email for merge commits | No | `radicle-mirror@users.noreply.github.com` |
| `pr-labels` | Comma-separated list of labels for PRs | No | |
| `github-token` | GitHub token for authentication | No | `${{ github.token }}` |

**Recommended: Use Your Own Seed**

For reliable syncing, we recommend running your own Radicle seed node and configuring it as a preferred seed. Public seeds may be slow to respond or temporarily unavailable, which can cause sync failures. Your repository must be seeded on the preferred seed before the action can fetch it.

To set up your own seed, see the [Radicle seed documentation](https://docs.radicle.xyz/guides/seeder).

## Setup Tutorial

### Step 1: Create a Radicle Identity for GitHub Actions

On your local machine, create a new Radicle identity for GitHub Actions:

```bash
# Create a persistent directory for the GitHub Actions identity
mkdir -p ~/.radicle-github-actions
export RAD_HOME="$HOME/.radicle-github-actions"
export RAD_PASSPHRASE=""

# Create the identity (empty passphrase via stdin)
rad auth --alias "github-actions-bot" --stdin < /dev/null

# Get the DID
DID=$(rad self --did)
echo "Machine DID: $DID"

# Export the keys as base64 (you'll need these for GitHub secrets)
echo "Private key (base64):"
base64 < "$RAD_HOME/keys/radicle"

echo "Public key (base64):"
base64 < "$RAD_HOME/keys/radicle.pub"

echo "Passphrase (base64 empty string):"
echo -n "" | base64

echo ""
echo "Keys are saved in: $RAD_HOME/keys"
echo "IMPORTANT: Back up this directory! GitHub secrets cannot be read back once set."
```

**Important**: Keep the `~/.radicle-github-actions` directory backed up somewhere safe. You'll need it if you ever need to recreate the secrets or perform manual Radicle operations with this identity.

Now, back in your **main** Radicle identity, add the machine identity as a delegate:

```bash
# Switch back to your main identity
unset RAD_HOME

# In your repository, add the GitHub Actions identity as a delegate
rad id update --title "Add GitHub Actions mirror account" \
  --description "Machine account for GitHub Actions mirroring" \
  --delegate "$DID" --threshold 1

# Sync to network
rad sync --announce
```

### Step 2: Initialize or Get Your Radicle Repository

If you haven't already published your repository to Radicle:

```bash
# In your repository
rad init --name "my-project" --description "My awesome project"
```

Get the repository information:

```bash
# Get the repository ID (rad:xxx)
rad inspect

# Get the project name
rad inspect --payload | jq -r '.xyz.radicle.project.name'
```

### Step 3: Set Up GitHub Secrets

**Option A: Using GitHub CLI (gh)**

```bash
# First, create the 'radicle' environment
gh api repos/$(gh repo view --json nameWithOwner -q .nameWithOwner)/environments/radicle -X PUT

# Set environment secrets (identity-related)
export RAD_HOME="$HOME/.radicle-github-actions"
gh secret set RADICLE_IDENTITY_ALIAS --env radicle -b "github-actions-bot"
gh secret set RADICLE_IDENTITY_PASSPHRASE --env radicle < <(echo -n "" | base64)
gh secret set RADICLE_IDENTITY_PRIVATE_KEY --env radicle < <(base64 < "$RAD_HOME/keys/radicle")
gh secret set RADICLE_IDENTITY_PUBLIC_KEY --env radicle < <(base64 < "$RAD_HOME/keys/radicle.pub")

# Set repository secrets (project info)
unset RAD_HOME  # Use main identity
gh secret set RADICLE_PROJECT_NAME -b "$(rad inspect --payload | jq -r '.xyz.radicle.project.name')"
gh secret set RADICLE_REPOSITORY_ID -b "$(rad inspect)"

# Verify secrets were created
gh secret list
```

**Note**: GitHub secrets cannot be read back once set for security reasons. You can only verify they exist with `gh secret list`.

**Option B: Using GitHub Web UI**

First, create the "radicle" environment at **Settings → Environments → New environment**.

Then add these **Environment secrets** (under the "radicle" environment):

| Secret | Value |
|--------|-------|
| `RADICLE_IDENTITY_ALIAS` | `github-actions-bot` |
| `RADICLE_IDENTITY_PASSPHRASE` | Base64 empty string (from Step 1) |
| `RADICLE_IDENTITY_PRIVATE_KEY` | Base64 private key from Step 1 |
| `RADICLE_IDENTITY_PUBLIC_KEY` | Base64 public key from Step 1 |

And these **Repository secrets** (under Actions secrets):

| Secret | Value |
|--------|-------|
| `RADICLE_PROJECT_NAME` | Project name from Step 2 |
| `RADICLE_REPOSITORY_ID` | Repository ID (rad:xxx) from Step 2 |

### Step 4 (Optional): Set Up GitHub App for Workflow Triggers

If you want PRs from Radicle to trigger your CI workflows:

1. Create a GitHub App at **Settings → Developer settings → GitHub Apps → New GitHub App**
2. Set permissions: **Contents** (Read & Write), **Pull Requests** (Read & Write)
3. Generate a private key and save it
4. Install the app on your repository
5. Add these secrets:
   - `APP_ID` - Your GitHub App ID
   - `APP_PRIVATE_KEY` - The private key

Then use the GitHub App token in your workflow (see example in [Usage](#usage) section).

### Step 5: Create the Workflow

Create `.github/workflows/radicle.yaml` with the example from the [Usage](#usage) section.

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

## Learn More

- [Radicle Website](https://radicle.xyz)
- [Radicle Documentation](https://docs.radicle.xyz)
- [Get Started with Radicle](https://radicle.xyz/get-started)
