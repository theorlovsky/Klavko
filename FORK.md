# theorlovsky/Klavko — personal fork

A fork of [stepsergius/Klavko](https://github.com/stepsergius/Klavko), audited at upstream commit
`6510e64` and changed to be safer to run with the Accessibility permission.

## Changes from upstream

- **No auto-updater.** `Updater.swift` is gone, with its menu item, settings toggle and the
  `--update-test` / `--snapshot-update` developer flags. The app never downloads or replaces itself;
  it makes no network requests at all unless you turn on Google AI voice input or download the voice model.
- **No ad-hoc signing.** `scripts/build-app.sh` refuses to build without an Apple Development or
  Developer ID certificate and checks that the designated requirement names the certificate.
  Upstream's ad-hoc builds use `identifier "app.klavko.Klavko"` as the requirement, which lets any
  program signed ad hoc with that identifier inherit the Accessibility permission.
- **Clipboard history off by default.** It is stored as plain JSON on disk; turn it on in Settings if you want it.
- `scripts/share.sh` (upstream's ad-hoc release script) is replaced by `scripts/release.sh`.

## Installing

```sh
brew install --cask theorlovsky/tap/klavko
```

Then grant Accessibility in System Settings → Privacy & Security. The permission is tied to your
certificate, so it survives updates until the certificate is renewed (yearly for Apple Development).

Don't mix in `scripts/install.sh`: it copies a build into /Applications behind Homebrew's back.

## Releasing a new build

One-time: in Xcode → Settings → Accounts, add your Apple ID and create an **Apple Development**
certificate; `brew install gh && gh auth login`; `brew tap theorlovsky/tap`.

```sh
scripts/release.sh --dry-run   # build and zip only
scripts/release.sh             # publish fork-<version>-<commit>, update the cask, push the tap
brew update && brew upgrade --cask klavko
```

## Taking upstream changes

```sh
git remote add upstream https://github.com/stepsergius/Klavko.git   # once
git fetch upstream
git log --oneline main..upstream/main      # what's new
git diff main...upstream/main -- Sources scripts Package.swift Package.resolved
```

Review the diff before merging — especially anything touching networking, `Process`, the event tap,
the clipboard, signing or dependencies — then merge, push and run `scripts/release.sh`.
