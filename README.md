# IPTVMac

Public downloads and signed updates for the IPTVMac macOS application.
Application source is maintained separately in a private repository.

## Unnotarized release

The owner has chosen to distribute an **unnotarized, development-signed** build.
It is not signed with a Developer ID Application certificate and has not been
notarized by Apple. macOS may warn or block it; download verification does not
promise installation or first-launch acceptance. Neither the application nor
the download helper disables macOS security protections.

The current build targets Apple Silicon (arm64), macOS 14 or later. Intel and
Universal releases are not currently provided.

## First installation

Use the [Releases page](https://github.com/Musabaxmedov94/IPTVMac/releases)
or download the reviewed helper from `Scripts/install-release.sh`. The helper
uses stock macOS tools and requires curl 8.4 or later; it downloads and verifies
the release ZIP. It does **not** install, replace or launch an application.

```sh
installer_script=$(mktemp -t iptvmac-download)
curl -q --fail --show-error --proto '=https' --proto-redir '=https' \
  --connect-timeout 20 --max-time 60 --max-filesize 1048576 \
  --output "$installer_script" \
  'https://raw.githubusercontent.com/Musabaxmedov94/IPTVMac/main/Scripts/install-release.sh'
less "$installer_script"
/bin/zsh "$installer_script" --repo Musabaxmedov94/IPTVMac --download-only
```

The explicit `--download-only` option checks the SHA-256, archive safety,
architecture, bundle identity and publisher signature, but does not require
Developer ID/notarization acceptance. Without it, the helper's default
distribution-readiness checks reject this intentionally unnotarized build.

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

## Media runtime sources and licenses

The release uses dynamically linked LGPL builds of libmpv and FFmpeg, with
subtitle/rendering dependencies. Exact runtime source archives, build recipes,
checksums and third-party license notices are provided in the matching Release's
`IPTVMac-Runtime-Sources.zip`. Application source remains private. The app does
not include any personal M3U/Xtream subscription, provider password or channel
package; each user supplies their own provider connection.
