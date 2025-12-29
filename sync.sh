#!/usr/bin/env bash
set -euo pipefail

export RAD_HOME="${GITHUB_WORKSPACE}/.radicle"
export RAD_PASSPHRASE=""

# Install Radicle CLI
echo "::group::Install Radicle CLI"
if command -v rad >/dev/null 2>&1; then
  echo "Radicle CLI already available"
else
  curl --show-error --silent --fail https://radicle.xyz/install | sh
  export PATH="$HOME/.radicle/bin:$PATH"
fi
rad --version
echo "::endgroup::"

# Setup Radicle Identity
echo "::group::Setup Radicle Identity"
rad config init --alias "$RADICLE_IDENTITY_ALIAS"
echo "$RADICLE_IDENTITY_PRIVATE_KEY" | base64 --decode > "${RAD_HOME}/keys/radicle"
echo "$RADICLE_IDENTITY_PUBLIC_KEY" | base64 --decode > "${RAD_HOME}/keys/radicle.pub"
chmod 600 "${RAD_HOME}/keys/radicle"
rad auth
echo "::endgroup::"

# Configure Preferred Seeds
if [ -n "$PREFERRED_SEEDS" ]; then
  echo "::group::Configure Preferred Seeds"
  jq --arg seeds "$PREFERRED_SEEDS" '.preferredSeeds = ($seeds | split(",") | map(gsub("^\\s+|\\s+$"; "")))' \
    "${RAD_HOME}/config.json" > "${RAD_HOME}/config.json.tmp"
  mv "${RAD_HOME}/config.json.tmp" "${RAD_HOME}/config.json"
  echo "::endgroup::"
fi

# Start Radicle Node
echo "::group::Start Radicle Node"
rad self
rad node start
echo "::endgroup::"

# Fetch Radicle Repository
echo "::group::Fetch Radicle Repository"
REPO_STORAGE_PATH="${RAD_HOME}/storage/${RADICLE_REPOSITORY_ID#rad:}"
rad seed "$RADICLE_REPOSITORY_ID" --scope all

for attempt in 1 2 3 4 5; do
  echo "Fetch attempt $attempt/5..."
  rad sync --fetch "$RADICLE_REPOSITORY_ID" --timeout 30 || true
  [ -d "$REPO_STORAGE_PATH" ] && break
  sleep 5
done

if [ ! -d "$REPO_STORAGE_PATH" ]; then
  echo "::error::Repository $RADICLE_REPOSITORY_ID not found after fetch attempts."
  echo "::error::Ensure you have initialized and synced the repository on Radicle first."
  exit 1
fi
echo "::endgroup::"

# Clone GitHub repo and connect to Radicle
echo "::group::Connect to Radicle"
git clone "https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" "$RADICLE_PROJECT_NAME"
cd "$RADICLE_PROJECT_NAME"
git config user.name "$GIT_USER_NAME"
git config user.email "$GIT_USER_EMAIL"
echo -n "" | rad init --existing "$RADICLE_REPOSITORY_ID" --no-confirm
echo "::endgroup::"

# Sync between GitHub and Radicle
echo "::group::Sync"
git fetch rad "$GITHUB_REF_NAME" 2>/dev/null || true

RADICLE_COMMITS=0
if git rev-parse --verify "rad/$GITHUB_REF_NAME" >/dev/null 2>&1; then
  RADICLE_COMMITS=$(git rev-list "HEAD..rad/$GITHUB_REF_NAME" --count)
fi

if [ "$RADICLE_COMMITS" -eq 0 ]; then
  echo "Pushing GitHub changes to Radicle..."
  git push rad "HEAD:$GITHUB_REF_NAME"
else
  echo "Radicle has $RADICLE_COMMITS new commit(s), creating PR..."
  BRANCH_NAME="radicle-sync/$GITHUB_REF_NAME"
  git checkout -b "$BRANCH_NAME"

  if git merge --no-edit "rad/$GITHUB_REF_NAME"; then
    BODY="This PR contains changes contributed to Radicle."
  else
    git merge --abort
    git merge --no-edit "rad/$GITHUB_REF_NAME" || true
    BODY="⚠️ **Merge conflict** - please resolve manually."
  fi

  git push --force origin "$BRANCH_NAME"

  if ! gh pr list --head "$BRANCH_NAME" --base "$GITHUB_REF_NAME" | grep -q .; then
    PR_ARGS=(--title "Sync from Radicle to $GITHUB_REF_NAME" --body "$BODY" --base "$GITHUB_REF_NAME" --head "$BRANCH_NAME")
    [ -n "$PR_LABELS" ] && PR_ARGS+=(--label "$PR_LABELS")
    gh pr create "${PR_ARGS[@]}"
  fi
fi

rad sync --announce --timeout 60 || true
rad node stop
echo "::endgroup::"
