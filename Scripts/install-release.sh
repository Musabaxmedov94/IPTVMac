#!/bin/zsh
# Public GitHub release download/verification helper, not an app replacer.
# No third-party dependencies or curl | shell. No installation or app launch.
set -euo pipefail
umask 077

fail() { print -u2 -- "IPTVMac release helper: $*"; exit 1; }
# BEGIN RELEASE_ARCHIVE_VALIDATION
# Pinned Sparkle 2.10.1 framework links only. No arbitrary relative links,
# absolute destinations, traversal, symlink descendants or special files.
sparkle_link_target() {
  local prefix='IPTVMac.app/Contents/Frameworks/Sparkle.framework'
  case "$1" in
    "$prefix/Versions/Current") print -rn -- 'B' ;;
    "$prefix/Autoupdate") print -rn -- 'Versions/Current/Autoupdate' ;;
    "$prefix/Headers") print -rn -- 'Versions/Current/Headers' ;;
    "$prefix/Modules") print -rn -- 'Versions/Current/Modules' ;;
    "$prefix/PrivateHeaders") print -rn -- 'Versions/Current/PrivateHeaders' ;;
    "$prefix/Resources") print -rn -- 'Versions/Current/Resources' ;;
    "$prefix/Sparkle") print -rn -- 'Versions/Current/Sparkle' ;;
    "$prefix/Updater.app") print -rn -- 'Versions/Current/Updater.app' ;;
    "$prefix/XPCServices") print -rn -- 'Versions/Current/XPCServices' ;;
    *) return 1 ;;
  esac
}
release_entry_name_valid() {
  local entry_name="$1"
  [[ -n "$entry_name" && "$entry_name" != *[^A-Za-z0-9._/+\ @-]* ]] || fail 'The ZIP contains an unsafe entry name.'
  [[ "$entry_name" != /* && "$entry_name" != *'//'* && "/$entry_name/" != *'/../'* && "/$entry_name/" != *'/./'* ]] || fail 'ZIP path traversal was rejected.'
  case "$entry_name" in
    IPTVMac.app|IPTVMac.app/|IPTVMac.app/*|__MACOSX/|__MACOSX/IPTVMac.app/) ;;
    __MACOSX/IPTVMac.app/*)
      [[ "$entry_name" == */ || "${entry_name:t}" == ._* ]] || fail 'Only AppleDouble metadata is allowed outside the app.' ;;
    *) fail 'The ZIP contains a file outside IPTVMac.app.' ;;
  esac
}
release_validate_tree() {
  local app_bundle="$1" bundle_entry entry_name expected_target resolved_entry
  [[ -d "$app_bundle" && ! -L "$app_bundle" ]] || fail 'The app root must be an ordinary directory.'
  while IFS= read -r -d '' bundle_entry; do
    entry_name="IPTVMac.app${bundle_entry#$app_bundle}"
    release_entry_name_valid "$entry_name"
    if [[ -L "$bundle_entry" ]]; then
      expected_target="$(sparkle_link_target "$entry_name")" || fail 'An unapproved symbolic link was rejected.'
      [[ "$(/usr/bin/readlink "$bundle_entry")" == "$expected_target" ]] || fail 'A Sparkle symbolic link has an unexpected destination.'
      resolved_entry="${bundle_entry:A}"
      [[ ( "$resolved_entry" == "$app_bundle/Contents/Frameworks/Sparkle.framework/Versions/B" || "$resolved_entry" == "$app_bundle/Contents/Frameworks/Sparkle.framework/Versions/B/"* ) && -e "$resolved_entry" ]] || fail 'A Sparkle symbolic link is dangling or escapes its framework.'
    elif [[ ! -f "$bundle_entry" && ! -d "$bundle_entry" ]]; then
      fail 'The app contains a special file.'
    fi
  done < <(/usr/bin/find "$app_bundle" -print0)
}
release_validate_archive() {
  local archive_file="$1" scratch_directory="$2"
  local entry_list="$scratch_directory/entries.txt" entry_details="$scratch_directory/entry-details.txt"
  local entry_types="$scratch_directory/entry-types.txt" entry_count=0
  local entry_name entry_type expected_target link_path canonical_destination
  local -a link_paths=()
  /usr/bin/zipinfo -1 "$archive_file" > "$entry_list" || fail 'Could not list the ZIP archive.'
  /usr/bin/zipinfo -l "$archive_file" > "$entry_details" || fail 'Could not inspect ZIP entry attributes.'
  while IFS= read -r entry_name; do
    (( entry_count += 1 ))
    (( entry_count <= 10000 )) || fail 'The ZIP has too many entries.'
    release_entry_name_valid "$entry_name"
  done < "$entry_list"
  (( entry_count > 0 )) || fail 'The ZIP is empty.'
  [[ -z "$(/usr/bin/sort "$entry_list" | /usr/bin/uniq -d)" ]] || fail 'The ZIP contains duplicate paths.'
  /usr/bin/awk -v expected_count="$entry_count" '
    $2 ~ /^[0-9]+[.][0-9]+$/ {
      count++
      if ($3 != "unx" || $1 !~ /^[-dl][rwxstST-]+$/ || length($1) != 10 || $4 !~ /^[0-9]+$/ || $5 !~ /^[bt][-xX]$/ || ($7 != "stor" && $7 != "defN")) bad=1
      if (substr($1, 1, 1) == "l" && ($4 < 1 || $4 > 128)) bad=1
      total += $4
      if (total > 2147483648) bad=1
    }
    END { if (count != expected_count || bad || total <= 0) exit 1 }
  ' "$entry_details" || fail 'The ZIP has encrypted/special/unsupported entries, or exceeds the 2 GiB declared extracted-size limit.'
  /usr/bin/awk '$2 ~ /^[0-9]+[.][0-9]+$/ { print substr($1, 1, 1) }' "$entry_details" > "$entry_types"
  while IFS=$'\t' read -r entry_name entry_type; do
    if [[ "$entry_type" == d ]]; then
      [[ "$entry_name" == */ ]] || fail 'A ZIP directory has no directory suffix.'
    else
      [[ "$entry_name" != */ ]] || fail 'A ZIP file has an invalid directory suffix.'
    fi
    if [[ "$entry_type" == l ]]; then
      expected_target="$(sparkle_link_target "$entry_name")" || fail 'An unapproved ZIP symbolic link was rejected.'
      /usr/bin/unzip -p "$archive_file" "$entry_name" | /bin/dd bs=1 count=129 of="$scratch_directory/link-target" 2>/dev/null || fail 'Could not read a bounded ZIP symbolic link.'
      /usr/bin/cmp -s "$scratch_directory/link-target" <(print -rn -- "$expected_target") || fail 'A ZIP symbolic link has an unexpected destination.'
      link_paths+=("$entry_name")
      if [[ "$entry_name" == */Versions/Current ]]; then
        canonical_destination="${entry_name:h}/B/"
      else
        canonical_destination="${entry_name:h}/Versions/B/${entry_name:t}"
        case "${entry_name:t}" in Autoupdate|Sparkle) ;; *) canonical_destination+='/' ;; esac
      fi
      /usr/bin/grep -Fqx -- "$canonical_destination" "$entry_list" || fail 'A ZIP symbolic link has no canonical in-framework destination.'
    fi
  done < <(/usr/bin/paste "$entry_list" "$entry_types")
  while IFS= read -r entry_name; do
    for link_path in "${link_paths[@]}"; do
      [[ "$entry_name" != "$link_path/"* ]] || fail 'ZIP entries beneath a symbolic link were rejected.'
    done
  done < "$entry_list"
}
# END RELEASE_ARCHIVE_VALIDATION
usage() {
  print 'Usage: /bin/zsh install-release.sh --repo OWNER/IPTVMac [--download-only]'
  print 'Uses only a published public GitHub latest release and its API SHA-256 digest.'
  print 'Saves a verified ZIP to a new Downloads subfolder; never installs or launches an app.'
  print -- '--download-only skips the distribution-readiness gate, not identity/SHA-256 checks.'
}

repository=''
download_only=false
while (( $# )); do
  case "$1" in
    --repo) (( $# >= 2 )) || { usage >&2; exit 2; }; repository="$2"; shift 2 ;;
    --download-only) download_only=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done
[[ "$OSTYPE" == darwin* ]] || fail 'This release helper requires macOS.'
[[ "$repository" =~ '^[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9][A-Za-z0-9._-]{0,99}$' ]] || fail 'Supply the real public GitHub OWNER/IPTVMac repository; the account owner is never guessed.'
[[ "${repository:t}" != '.' && "${repository:t}" != '..' ]] || fail 'Invalid repository name.'
[[ -n "${HOME:-}" && "$HOME" == /* && -d "$HOME" && ! -L "$HOME" ]] || fail 'A normal, absolute user home directory is required.'
# curl before 8.4 did not apply --max-filesize to transfers in progress when
# Content-Length was absent. Fail before any request on older stock macOS curl.
curl_version_output="$(/usr/bin/curl -q --version)"
curl_version="${${curl_version_output#curl }%% *}"
[[ "$curl_version" =~ '^[0-9]{1,4}[.][0-9]{1,4}[.][0-9]{1,4}$' ]] || fail 'The stock curl version is not understood.'
curl_version_components=("${(@s:.:)curl_version}")
(( curl_version_components[1] > 8 || (curl_version_components[1] == 8 && curl_version_components[2] >= 4) )) || fail 'For a bounded download, stock macOS curl 8.4.0 or newer is required. Update macOS, or download the release manually from the official repository; this helper made no network request.'

expected_identifier='com.musab.iptv'
expected_team='K7VJP8Z8UJ'
signing_requirement="anchor apple generic and identifier \"$expected_identifier\" and certificate leaf[subject.OU] = \"$expected_team\""
distribution_requirement="$signing_requirement and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
maximum_archive_bytes=536870912
temporary_directory="$(/usr/bin/mktemp -d /private/tmp/IPTVMac-install.XXXXXX)"
retained_download_directory=''
cleanup() {
  if [[ -n "${temporary_directory:-}" && "$temporary_directory" == /private/tmp/IPTVMac-install.* && -d "$temporary_directory" && ! -L "$temporary_directory" ]]; then
    /bin/rm -rf -- "$temporary_directory"
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

canonical_version() {
  [[ "$1" =~ '^(0|[1-9][0-9]{0,4})[.](0|[1-9][0-9]{0,4})[.](0|[1-9][0-9]{0,4})$' ]]
}
json_string() { /usr/bin/plutil -extract "$1" raw -expect string -o - "$2" 2>/dev/null; }
json_integer() { /usr/bin/plutil -extract "$1" raw -expect integer -o - "$2" 2>/dev/null; }

# Manually follow only the known GitHub release-asset hosts. HTTPS alone is not
# a redirect allowlist; curl --location would otherwise allow any HTTPS host.
download_https() {
  local request_url="$1" output_file="$2" maximum_bytes="$3" request_kind="$4"
  local response_info http_status redirect_url redirect_count
  for redirect_count in 0 1 2 3; do
    case "$request_kind:$request_url" in
      api:https://api.github.com/repos/"$repository"/releases/latest) ;;
      asset:https://github.com/"$repository"/releases/download/"$release_tag"/"$asset_name") ;;
      asset:https://release-assets.githubusercontent.com/*|asset:https://objects.githubusercontent.com/*) ;;
      *) fail 'A download or redirect did not match the GitHub HTTPS allowlist.' ;;
    esac
    [[ "$request_url" != *[$'\r\n\t ']* && "$request_url" != *'#'* && "$request_url" != *$'\\'* ]] || fail 'An unsafe download URL was rejected.'
    if ! response_info="$(/usr/bin/curl -q --silent --show-error --fail --proto '=https' --proto-redir '=https' \
      --connect-timeout 20 --max-time 600 --max-redirs 0 --max-filesize "$maximum_bytes" \
      --header 'Accept: application/vnd.github+json' --header 'X-GitHub-Api-Version: 2022-11-28' \
      --output "$output_file" --write-out $'%{http_code}\n%{redirect_url}' --url "$request_url")"; then
      if [[ "$request_kind" == api && "${response_info%%$'\n'*}" == 404 ]]; then
        fail 'No stable public Release is available at this repository. The download helper exists, but the app ZIP must be published first. Nothing was installed.'
      fi
      fail 'GitHub download failed. Check the public repository, network, and unauthenticated API rate limit; nothing was installed.'
    fi
    http_status="${response_info%%$'\n'*}"
    redirect_url="${response_info#*$'\n'}"
    if [[ "$http_status" == 200 ]]; then
      local received_bytes="$(/usr/bin/stat -f '%z' "$output_file")"
      (( received_bytes > 0 && received_bytes <= maximum_bytes )) || fail 'The downloaded file is empty or too large.'
      return 0
    fi
    [[ "$request_kind" == asset && "$http_status" == (301|302|303|307|308) && -n "$redirect_url" && "$redirect_url" != "$response_info" ]] || fail 'GitHub returned an unexpected response.'
    request_url="$redirect_url"
  done
  fail 'Too many download redirects.'
}

release_json="$temporary_directory/release.json"
print -- "Checking the latest public release in $repository…"
download_https "https://api.github.com/repos/$repository/releases/latest" "$release_json" 1048576 api
# plutil -lint only validates property-list input; it rejects valid GitHub JSON.
# JSON conversion validates input while preserving GitHub's ordinary null fields.
validated_release_json="$temporary_directory/validated-release.json"
/usr/bin/plutil -convert json -o "$validated_release_json" "$release_json" >/dev/null || fail 'GitHub returned invalid release metadata.'
release_json="$validated_release_json"
[[ "$(/usr/bin/plutil -extract draft raw -expect bool -o - "$release_json" 2>/dev/null)" == false ]] || fail 'Draft releases are not installable.'
[[ "$(/usr/bin/plutil -extract prerelease raw -expect bool -o - "$release_json" 2>/dev/null)" == false ]] || fail 'Prereleases are not installed by the stable channel.'
release_tag="$(json_string tag_name "$release_json")" || fail 'The release tag is missing.'
[[ "$release_tag" == v* ]] || fail 'Release tags must use vMAJOR.MINOR.PATCH.'
release_version="${release_tag#v}"
canonical_version "$release_version" || fail 'The latest release has an unsupported version tag.'
[[ "$(json_string html_url "$release_json")" == "https://github.com/$repository/releases/tag/$release_tag" ]] || fail 'The release page URL does not belong to the selected repository and tag.'

if [[ "$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null || print 0)" == 1 ]]; then
  architecture='arm64'
else
  architecture="$(/usr/bin/uname -m)"
fi
[[ "$architecture" == arm64 || "$architecture" == x86_64 ]] || fail 'This Mac architecture is not supported.'
asset_name="IPTVMac-macos-$architecture.zip"
asset_index=0
matching_assets=0
download_url=''
expected_digest=''
expected_size=''
while (( asset_index < 1000 )); do
  candidate_name="$(json_string "assets.$asset_index.name" "$release_json")" || break
  if [[ "$candidate_name" == "$asset_name" ]]; then
    (( matching_assets += 1 ))
    [[ "$(json_string "assets.$asset_index.state" "$release_json")" == uploaded ]] || fail 'The release archive is not a completed uploaded asset.'
    download_url="$(json_string "assets.$asset_index.browser_download_url" "$release_json")" || fail 'The archive download URL is missing.'
    expected_digest="$(json_string "assets.$asset_index.digest" "$release_json")" || fail 'GitHub did not provide an archive SHA-256 digest. Re-upload this release asset; checksum-only fallback is not accepted.'
    expected_size="$(json_integer "assets.$asset_index.size" "$release_json")" || fail 'The archive size is missing.'
  fi
  (( asset_index += 1 ))
done
(( matching_assets == 1 )) || fail "The release must contain exactly one $asset_name asset. A different architecture will not be installed."
[[ "$download_url" == "https://github.com/$repository/releases/download/$release_tag/$asset_name" ]] || fail 'The archive URL does not belong to the selected repository and tag.'
[[ "$expected_digest" =~ '^sha256:[a-fA-F0-9]{64}$' ]] || fail 'The GitHub archive digest is not SHA-256.'
[[ "$expected_size" =~ '^[1-9][0-9]{0,9}$' ]] || fail 'The archive size is invalid.'
(( expected_size <= maximum_archive_bytes )) || fail 'The archive exceeds the 512 MiB download limit.'

archive_file="$temporary_directory/$asset_name"
print -- "Downloading IPTVMac $release_version for $architecture…"
download_https "$download_url" "$archive_file" "$maximum_archive_bytes" asset
[[ "$(/usr/bin/stat -f '%z' "$archive_file")" == "$expected_size" ]] || fail 'The archive size does not match GitHub metadata.'
actual_digest="$(/usr/bin/shasum -a 256 "$archive_file")"
actual_digest="${actual_digest%% *}"
[[ "${actual_digest:l}" == "${${expected_digest#sha256:}:l}" ]] || fail 'The archive SHA-256 does not match GitHub metadata.'

# Preflight the complete archive before ditto sees a single entry. This allows
# only the nine inspected Sparkle framework links with their exact destinations.
release_validate_archive "$archive_file" "$temporary_directory"

extraction_directory="$temporary_directory/extracted"
/bin/mkdir "$extraction_directory"
/usr/bin/ditto -x -k "$archive_file" "$extraction_directory" || fail 'Could not extract the verified ZIP.'
app_bundle="$extraction_directory/IPTVMac.app"
[[ -d "$app_bundle" && ! -L "$app_bundle" ]] || fail 'The ZIP did not contain the expected app.'
release_validate_tree "$app_bundle"
[[ ! -e "$extraction_directory/__MACOSX" || -z "$(/usr/bin/find "$extraction_directory/__MACOSX" ! -type f ! -type d -print -quit)" ]] || fail 'The extracted metadata contains links or special files.'
info_file="$app_bundle/Contents/Info.plist"
[[ -f "$info_file" && ! -L "$info_file" ]] || fail 'The app Info.plist is missing.'
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_file")" == "$expected_identifier" ]] || fail 'The app has the wrong bundle identifier.'
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_file")" == "$release_version" ]] || fail 'The app version does not match the release tag.'
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$info_file")" == IPTVMac ]] || fail 'The app executable name is invalid.'
[[ "$(/usr/bin/file -b "$app_bundle/Contents/MacOS/IPTVMac")" == "Mach-O 64-bit executable $architecture" ]] || fail 'The actual executable architecture does not match this release asset.'
/usr/bin/codesign --verify --deep --strict --verbose=2 -R="$signing_requirement" "$app_bundle" || fail 'The app signature, Apple trust chain, or signing team did not verify.'

retain_download() {
  local downloads_directory="$HOME/Downloads"
  [[ -d "$downloads_directory" && ! -L "$downloads_directory" ]] || fail 'The Downloads directory must already exist and must not be a symlink.'
  retained_download_directory="$(/usr/bin/mktemp -d "$downloads_directory/IPTVMac-$release_version.XXXXXX")"
  /bin/mv "$archive_file" "$retained_download_directory/$asset_name"
  print -- "Verified archive saved to: $retained_download_directory/$asset_name"
}
if [[ "$download_only" == true ]]; then
  print 'Download-only mode: Developer ID/notarization acceptance is not required by this command. macOS may warn or block the app; launch approval is your decision.'
  retain_download
  print 'Bundle identifier, version, architecture, SHA-256, and Apple/team signature verified. No application was installed or launched.'
  print 'The app has not been notarized by this helper. Open it normally in Finder and follow macOS approval. This command does not disable security protections.'
  exit 0
fi

# No xattr removal, ad-hoc re-signing, or Gatekeeper bypass is permitted.
if ! /usr/bin/codesign --verify --deep --strict -R="$distribution_requirement" "$app_bundle"; then
  retain_download
  fail 'This build is not signed for Developer ID Application distribution. The developer must finish release signing; installation was not attempted.'
fi
if ! /usr/sbin/spctl --assess --type execute --verbose=2 "$app_bundle"; then
  retain_download
  fail 'macOS did not accept this app for distribution. The developer must finish Developer ID signing/notarization; installation was not attempted. Do not disable Gatekeeper or remove quarantine.'
fi
retain_download
print -- "IPTVMac $release_version passed the release checks. No app was installed or launched."
print 'To install: quit IPTVMac normally with Cmd+Q, open the ZIP in Finder, and move IPTVMac.app to your Applications folder.'
print 'Replace only the same IPTVMac app after checking its version; keep a recoverable copy of the prior app until the new one works.'
print 'Do not remove Application Support or Keychain data. Open the app normally and follow macOS approval; do not bypass launch warnings.'
