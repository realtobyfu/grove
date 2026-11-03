#!/bin/sh
# Xcode Cloud runs this right after cloning the repo, before it resolves
# packages or opens the project. The .xcodeproj / .xcworkspace are gitignored
# (Tuist-managed), so we have to generate them here or the build finds nothing.
#
# Everything here downloads over the network, and Xcode Cloud runners hit
# transient TLS failures (curl exit 35) often enough to break builds. So each
# fetch retries, and Homebrew stands in if mise can't be reached at all.
set -e

cd "$CI_PRIMARY_REPOSITORY_PATH"

export PATH="$HOME/.local/bin:$PATH"
TUIST="" # set to the command used to invoke tuist

# Download to a file rather than piping into sh: a pipeline reports the exit
# status of `sh`, so `curl ... | sh` silently swallows a failed download and
# fails later somewhere far less obvious.
echo "--- Installing mise ---"
if curl -fsSL --connect-timeout 30 --retry 5 --retry-delay 3 --retry-all-errors \
    https://mise.run -o "${TMPDIR:-/tmp}/mise-install.sh"; then
    if sh "${TMPDIR:-/tmp}/mise-install.sh"; then
        echo "--- Installing pinned tools (see mise.toml) ---"
        # mise fetches tuist over the network too, so give it the same leeway.
        for attempt in 1 2 3; do
            if mise install; then
                TUIST="mise exec -- tuist"
                break
            fi
            echo "mise install failed (attempt $attempt), retrying..."
            sleep $((attempt * 5))
        done
    fi
fi

if [ -z "$TUIST" ]; then
    # Homebrew is preinstalled on Xcode Cloud runners. This ignores the version
    # pinned in mise.toml, so a build that lands here may use a different tuist
    # than local builds — noisy on purpose, since that difference can matter.
    echo "--- WARNING: mise unavailable, falling back to Homebrew tuist ---"
    echo "--- (version pin in mise.toml is NOT honored on this path) ---"
    brew install tuist
    TUIST="tuist"
fi

echo "--- Generating Xcode project (via: $TUIST) ---"
$TUIST generate --no-open

# SQLiteData's macros and plugins have to be trusted on a runner with nobody to
# click the prompt.
defaults write com.apple.dt.Xcode IDESkipPackagePluginFingerprintValidatation -bool YES
defaults write com.apple.dt.Xcode IDESkipMacroFingerprintValidation -bool YES

# Xcode Cloud builds with automatic package resolution off and fails without a
# Package.resolved in the workspace. The workspace is generated, so it has none
# until this runs.
echo "--- Resolving packages ---"
for attempt in 1 2 3; do
    if xcodebuild -resolvePackageDependencies -workspace grove.xcworkspace -scheme grove; then
        break
    fi
    if [ "$attempt" = 3 ]; then
        echo "Package resolution failed after 3 attempts" >&2
        exit 1
    fi
    echo "Package resolution failed (attempt $attempt), retrying..."
    sleep $((attempt * 5))
done

echo "--- Done ---"
