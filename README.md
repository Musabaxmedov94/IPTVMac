# IPTVMac

Public downloads and signed updates for the IPTVMac macOS application.
Application source is maintained separately in a private repository.

## Release status

No installable public release has been published yet. The application and
in-app updater are being verified; Developer ID distribution signing,
notarization and an actual version-to-version update test are still required.
Do not treat this repository as proof that a download is ready.

The current build targets Apple Silicon (arm64), macOS 14 or later. Intel and
Universal releases are not currently provided.

## First installation

Once a release is published, use the [Releases page](https://github.com/Musabaxmedov94/IPTVMac/releases)
or download the reviewed helper from `Scripts/install-release.sh`. The helper
uses stock macOS tools and requires curl 8.4 or later; it downloads and verifies
the release ZIP. It does **not** install, replace or launch an application.

```sh
installer_script="$(mktemp "$HOME/Downloads/install-iptvmac.XXXXXX")"
curl -q --fail --show-error --proto '=https' --proto-redir '=https' \
  --connect-timeout 20 --max-time 60 --max-filesize 1048576 \
  --output "$installer_script" \
  'https://raw.githubusercontent.com/Musabaxmedov94/IPTVMac/main/Scripts/install-release.sh'
less "$installer_script"
/bin/zsh "$installer_script" --repo Musabaxmedov94/IPTVMac
```

Quit an existing IPTVMac normally, then install only the verified `IPTVMac.app`
using Finder. Follow the normal macOS approval process. If macOS rejects the
release, stop and report it; do not disable Gatekeeper or remove quarantine.
Installation replaces the application bundle, not playlists or account data.

## Future updates

After installing an updater-enabled build, choose **Check for Updates…** in the
application menu, then **Install Update**. Sparkle's native window verifies the
signed update, asks for confirmation, installs it, and relaunches IPTVMac.
An update requires both a newer stable GitHub Release and a matching signed
`appcast.xml`; pushing source code alone does not publish an app update.

This repository contains no GitHub login token, TMDB token, Apple signing key,
Firebase administrator key, provider credentials or user library. Sparkle's
license and attribution are included with the application bundle.
