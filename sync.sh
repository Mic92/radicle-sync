#!/usr/bin/env bash
set -euo pipefail

# GitHub Actions log grouping helpers
group() {
  echo "::group::$1"
}

endgroup() {
  echo "::endgroup::"
}

# Install Radicle CLI if not already available
group "Install Radicle CLI"
if command -v rad >/dev/null 2>&1; then
  echo "Radicle CLI already available in PATH, skipping installation"
  rad --version
else
  echo "Installing Radicle CLI..."
  curl --show-error --silent --fail https://radicle.xyz/install | sh
  # The installer puts radicle in ~/.radicle/bin
  export PATH="$HOME/.radicle/bin:$PATH"
fi

export RAD_HOME="${GITHUB_WORKSPACE}/.radicle"
export RAD_PASSPHRASE=""
endgroup

# Setup Radicle Identity
group "Setup Radicle Identity"
rad --version
rad config init --alias "$RADICLE_IDENTITY_ALIAS"

echo "$RADICLE_IDENTITY_PRIVATE_KEY" | base64 --decode > "${RAD_HOME}/keys/radicle"
echo "$RADICLE_IDENTITY_PUBLIC_KEY" | base64 --decode > "${RAD_HOME}/keys/radicle.pub"
chmod 600 "${RAD_HOME}/keys/radicle"

rad auth
endgroup

# Configure Preferred Seeds
if [ -n "$PREFERRED_SEEDS" ]; then
  group "Configure Preferred Seeds"
  CONFIG_FILE="${RAD_HOME}/config.json"

  SEEDS_JSON="[]"
  IFS=',' read -ra SEEDS <<< "$PREFERRED_SEEDS"
  for seed in "${SEEDS[@]}"; do
    seed=$(echo "$seed" | xargs)  # trim whitespace
    if [ -n "$seed" ]; then
      echo "Adding seed: $seed"
      SEEDS_JSON=$(echo "$SEEDS_JSON" | jq --arg s "$seed" '. + [$s]')
    fi
  done

  jq --argjson seeds "$SEEDS_JSON" '.preferredSeeds = $seeds' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp"
  mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
  endgroup
fi

# Start Radicle Node
group "Start Radicle Node"
rad self
rad node start
endgroup

# Fetch Radicle Repository into Storage
group "Fetch Radicle Repository into Storage"
REPO_STORAGE_PATH="${RAD_HOME}/storage/${RADICLE_REPOSITORY_ID#rad:}"

rad seed "$RADICLE_REPOSITORY_ID" --scope all

for attempt in 1 2 3 4 5; do
  echo "Fetch attempt $attempt/5..."
  rad sync --fetch "$RADICLE_REPOSITORY_ID" --timeout 30 || true
  [ -d "$REPO_STORAGE_PATH" ] && break
  sleep 5
done
endgroup

# Clone from GitHub and Connect to Radicle
group "Clone from GitHub and Connect to Radicle"
git clone "https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" "$RADICLE_PROJECT_NAME"
cd "$RADICLE_PROJECT_NAME"

git config user.name "$GIT_USER_NAME"
git config user.email "$GIT_USER_EMAIL"

# Check if repository exists in storage
if [ ! -d "$REPO_STORAGE_PATH" ]; then
  echo "::error::Repository $RADICLE_REPOSITORY_ID not found in storage after fetch attempt."
  echo "::error::Please ensure you have:"
  echo "::error::  1. Initialized the repository on Radicle with 'rad init'"
  echo "::error::  2. Added the GitHub Actions bot identity as a delegate"
  echo "::error::  3. Synced to the network with 'rad sync --announce'"
  echo "::error::See the tutorial in the README for detailed setup instructions."
  exit 1
fi

echo "Repository found in storage, connecting to existing Radicle repository..."
echo -n "" | rad init --existing "$RADICLE_REPOSITORY_ID" --no-confirm
endgroup

# Sync between GitHub and Radicle
group "Sync Between GitHub and Radicle"
git fetch rad "$GITHUB_REF_NAME" 2>/dev/null || echo "Branch doesn't exist on Radicle yet"

# Check if Radicle has commits not in GitHub
if git rev-parse --verify "rad/$GITHUB_REF_NAME" >/dev/null 2>&1; then
  RADICLE_COMMITS=$(git rev-list "HEAD..rad/$GITHUB_REF_NAME" --count)
else
  RADICLE_COMMITS=0
fi

if [ "$RADICLE_COMMITS" -eq 0 ]; then
  # Simple case: Radicle has no new commits, just push GitHub → Radicle
  echo "No new commits on Radicle, pushing GitHub changes..."
  git push rad "HEAD:$GITHUB_REF_NAME"
else
  # Radicle has new commits, create PR to bring them into GitHub
  echo "Radicle has $RADICLE_COMMITS new commit(s), creating PR..."

  BRANCH_NAME="radicle-sync/$GITHUB_REF_NAME"
  git checkout -b "$BRANCH_NAME"

  if git merge --no-edit "rad/$GITHUB_REF_NAME"; then
    echo "Merge successful, creating PR..."
    git push --force origin "$BRANCH_NAME"

    # Check if PR already exists, create if not
    if gh pr list --head "$BRANCH_NAME" --base "$GITHUB_REF_NAME" | grep -q .; then
      echo "PR already exists, updating it"
    else
      BODY="This PR contains changes that were contributed to Radicle.

Merge this PR to sync them back to GitHub."

      if [ -n "$PR_LABELS" ]; then
        gh pr create --title "Sync changes from Radicle to $GITHUB_REF_NAME" --body "$BODY" --base "$GITHUB_REF_NAME" --head "$BRANCH_NAME" --label "$PR_LABELS"
      else
        gh pr create --title "Sync changes from Radicle to $GITHUB_REF_NAME" --body "$BODY" --base "$GITHUB_REF_NAME" --head "$BRANCH_NAME"
      fi
    fi
  else
    # Merge failed due to conflicts
    echo "::error::Merge conflict detected between GitHub and Radicle."
    git merge --abort
    git merge --no-edit "rad/$GITHUB_REF_NAME" || true
    git push --force origin "$BRANCH_NAME"

    # Check if PR already exists, create if not
    if gh pr list --head "$BRANCH_NAME" --base "$GITHUB_REF_NAME" | grep -q .; then
      echo "PR already exists, updating it"
    else
      BODY="⚠️ **Merge conflict detected**

This PR contains changes from Radicle that conflict with GitHub. Please resolve conflicts manually."

      if [ -n "$PR_LABELS" ]; then
        gh pr create --title "Sync changes from Radicle to $GITHUB_REF_NAME" --body "$BODY" --base "$GITHUB_REF_NAME" --head "$BRANCH_NAME" --label "$PR_LABELS"
      else
        gh pr create --title "Sync changes from Radicle to $GITHUB_REF_NAME" --body "$BODY" --base "$GITHUB_REF_NAME" --head "$BRANCH_NAME"
      fi
    fi

    exit 1
  fi
fi

echo "Syncing with the network..."
rad sync --announce --timeout 60 || true

rad node stop
endgroup
