#!/bin/sh
# Xcode Cloud runs this right after cloning the repo, before it resolves
# packages or opens the project. The .xcodeproj / .xcworkspace are gitignored
# (Tuist-managed), so we have to generate them here or the build finds nothing.
set -e

echo "--- Installing mise ---"
curl -fsSL https://mise.run | sh
export PATH="$HOME/.local/bin:$PATH"

echo "--- Installing pinned tools (see mise.toml) ---"
cd "$CI_PRIMARY_REPOSITORY_PATH"
mise install

echo "--- Generating Xcode project ---"
mise exec -- tuist generate --no-open

echo "--- Done ---"
