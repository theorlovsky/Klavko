#!/bin/bash
# Fork release: builds Klavko on this Mac, signs it with your own certificate, publishes the zip as a
# GitHub release of the fork and points the Homebrew cask (theorlovsky/tap/klavko) at it.
#
#   scripts/release.sh            # build, publish, update the cask, push the tap
#   scripts/release.sh --dry-run  # build and zip only, print what would be published
#
# Needs: a clean main branch, Xcode or Command Line Tools, an Apple Development (or Developer ID)
# certificate in the login keychain, `gh` logged in, and the tap checked out by Homebrew
# (`brew tap theorlovsky/tap`).
set -euo pipefail
cd "$(dirname "$0")/.."

FORK_REPO="theorlovsky/Klavko"
TAP="theorlovsky/tap"
DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

fail() { echo "error: $*" >&2; exit 1; }

# Releases are built from exactly what is pushed, so the zip always matches a commit you can read.
[ -z "$(git status --porcelain)" ] || fail "uncommitted changes; commit or stash them first"
[ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || fail "release from main"
git fetch -q origin main
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || fail "main differs from origin/main; push or pull first"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
COMMIT="$(git rev-parse --short=10 HEAD)"
# Upstream may already have a v$VERSION tag in the fork: our tags carry the commit, so they never clash,
# and every new commit is a new cask version (brew upgrade notices it).
TAG="fork-$VERSION-$COMMIT"
CASK_VERSION="$VERSION,$COMMIT"

scripts/build-app.sh

mkdir -p dist
ZIP="dist/Klavko-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent build/Klavko.app "$ZIP"
SHA256="$(shasum -a 256 "$ZIP" | awk '{ print $1 }')"
echo "Packed $ZIP (sha256 $SHA256)"

if [ "$DRY_RUN" = 1 ]; then
    echo "dry run: would publish $TAG to $FORK_REPO and set cask version $CASK_VERSION"
    exit 0
fi

command -v gh >/dev/null || fail "gh is not installed (brew install gh)"
gh auth status >/dev/null 2>&1 || fail "gh is not logged in (gh auth login)"
TAP_DIR="$(brew --repo "$TAP")"
[ -d "$TAP_DIR/.git" ] || fail "tap $TAP is not checked out (brew tap $TAP)"

mkdir -p "$TAP_DIR/Casks"
cat > "$TAP_DIR/Casks/klavko.rb" <<CASK
cask "klavko" do
  version "$CASK_VERSION"
  sha256 "$SHA256"

  url "https://github.com/$FORK_REPO/releases/download/fork-#{version.csv.first}-#{version.csv.second}/Klavko-#{version.csv.first}.zip"
  name "Klavko"
  desc "Keyboard layout switcher and typing assistant (personal fork build)"
  homepage "https://github.com/$FORK_REPO"

  depends_on macos: :sonoma

  app "Klavko.app"

  # Signed with a personal certificate, not notarized: Gatekeeper would refuse the quarantined copy.
  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/Klavko.app"]
  end

  uninstall quit: "app.klavko.Klavko"

  zap trash: [
    "~/Library/Application Support/FluidAudio/Models/parakeet-ultra",
    "~/Library/Application Support/Klavko",
    "~/Library/Preferences/app.klavko.Klavko.plist",
  ]
end
CASK

# brew style switches Homebrew developer mode on: always switch it back off, even if style fails.
developer_off() {
    brew developer off >/dev/null 2>&1 || true
    git -C "$(brew --repo)" config --unset homebrew.devcmdrun 2>/dev/null || true
}
trap developer_off EXIT
# Fix what can be fixed, then require a clean run before anything is published or pushed.
brew style --fix "$TAP" || true
brew style "$TAP" || fail "brew style still reports offenses in $TAP_DIR/Casks/klavko.rb; nothing was published"
developer_off

# The cask is valid: publish the zip it points at, then push the cask.
gh release create "$TAG" "$ZIP" --repo "$FORK_REPO" --target "$(git rev-parse HEAD)" \
    --title "Klavko $VERSION ($COMMIT)" \
    --notes "Built from $FORK_REPO@$(git rev-parse HEAD), signed with a personal certificate. No auto-updater."

git -C "$TAP_DIR" add Casks/klavko.rb
git -C "$TAP_DIR" commit -m "klavko $CASK_VERSION"
git -C "$TAP_DIR" push

# The app is in the release and installed through brew from now on: don't leave a second, signed
# Klavko.app in the repo (Spotlight/Launch Services could start it instead of /Applications/Klavko.app).
rm -rf build/Klavko.app "$ZIP"

echo
echo "Released $TAG. Install or update with:"
echo "  brew update && brew install --cask $TAP/klavko   # first time"
echo "  brew update && brew upgrade --cask klavko         # later"
