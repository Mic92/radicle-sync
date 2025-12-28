# Mirror to Radicle

A GitHub Action that mirrors your code to the Radicle peer-to-peer code hosting network.

## Features

- Works on `ubuntu-slim` runners (no apt-get required)
- Supports custom preferred seeds
- Simple setup with GitHub secrets

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

## Inputs

| Input | Description | Required |
|-------|-------------|----------|
| `radicle-identity-alias` | Alias for your Radicle identity | Yes |
| `radicle-identity-passphrase` | Passphrase for the identity (base64 encoded) | Yes |
| `radicle-identity-private-key` | Private key (base64 encoded) | Yes |
| `radicle-identity-public-key` | Public key (base64 encoded) | Yes |
| `radicle-repository-id` | Repository ID (rad:xxx) | Yes |
| `radicle-project-name` | Project name | Yes |
| `preferred-seeds` | Comma-separated list of preferred seeds | No |

## Setup

See [gh-radicle](https://github.com/Mic92/dotfiles/tree/main/pkgs/gh-radicle) for a tool that automates the setup of GitHub secrets and workflow files.
