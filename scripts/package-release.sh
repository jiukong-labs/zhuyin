#!/bin/zsh

# Builds the public, universal Developer ID release, exports it with the
# production CloudKit entitlement, creates a signed installer package,
# notarizes it, staples the ticket, and writes a SHA-256 checksum.

set -euo pipefail

script_directory="${0:A:h}"
repository_root="${script_directory:h}"
project_path="$repository_root/Jiukong Zhuyin.xcodeproj"
scheme_name="Jiukong Zhuyin"
bundle_identifier="tw.idv.jiukong.inputmethod.zhuyin"
installation_directory="/Library/Input Methods"
entitlements_path="$repository_root/Resources/JiukongZhuyin.entitlements"
output_directory="${OUTPUT_DIRECTORY:-$repository_root/dist}"

usage() {
    cat <<'EOF'
Usage:
  DEVELOPER_ID_APPLICATION="Developer ID Application: Name (TEAMID)" \
  DEVELOPER_ID_INSTALLER="Developer ID Installer: Name (TEAMID)" \
  DEVELOPMENT_TEAM="TEAMID" \
  DEVELOPER_ID_PROVISIONING_PROFILE="Profile Name" \
  NOTARY_KEYCHAIN_PROFILE="jiukong-notary" \
  ./scripts/package-release.sh

Notary authentication may instead use all three of:
  NOTARY_KEY_FILE, NOTARY_KEY_ID, NOTARY_ISSUER_ID

Optional:
  RELEASE_TAG=v0.1.0          Require the bundle version to match this tag.
  OUTPUT_DIRECTORY=path      Write the package and checksum here.
  SIGNING_KEYCHAIN=path      Restrict productbuild to this keychain.
EOF
}

fail() {
    print -u2 "error: $*"
    exit 1
}

require_value() {
    local variable_name="$1"
    [[ -n "${(P)variable_name:-}" ]] || fail "$variable_name is required."
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "Required command is unavailable: $1"
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi
[[ $# -eq 0 ]] || fail "Unknown argument: $1 (use --help for usage)."

require_value DEVELOPER_ID_APPLICATION
require_value DEVELOPER_ID_INSTALLER
require_value DEVELOPMENT_TEAM
require_value DEVELOPER_ID_PROVISIONING_PROFILE

if [[ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
    notary_authentication=(--keychain-profile "$NOTARY_KEYCHAIN_PROFILE")
else
    require_value NOTARY_KEY_FILE
    require_value NOTARY_KEY_ID
    require_value NOTARY_ISSUER_ID
    [[ -f "$NOTARY_KEY_FILE" ]] || fail "NOTARY_KEY_FILE does not exist: $NOTARY_KEY_FILE"
    notary_authentication=(
        --key "$NOTARY_KEY_FILE"
        --key-id "$NOTARY_KEY_ID"
        --issuer "$NOTARY_ISSUER_ID"
    )
fi

[[ "$DEVELOPER_ID_APPLICATION" == "Developer ID Application:"* ]] \
    || fail "DEVELOPER_ID_APPLICATION must name a Developer ID Application identity."
[[ "$DEVELOPER_ID_INSTALLER" == "Developer ID Installer:"* ]] \
    || fail "DEVELOPER_ID_INSTALLER must name a Developer ID Installer identity."
[[ "$DEVELOPMENT_TEAM" =~ '^[A-Z0-9]{10}$' ]] \
    || fail "DEVELOPMENT_TEAM must be a 10-character Apple Team ID."
[[ -f "$project_path/project.pbxproj" ]] || fail "Xcode project is missing: $project_path"
[[ -f "$entitlements_path" ]] || fail "Entitlements file is missing: $entitlements_path"

for required_command in \
    /usr/bin/codesign \
    /usr/bin/lipo \
    /usr/bin/productbuild \
    /usr/bin/security \
    /usr/bin/shasum \
    /usr/sbin/pkgutil \
    /usr/sbin/spctl \
    /usr/libexec/PlistBuddy \
    xcodebuild \
    xcrun; do
    require_command "$required_command"
done

identity_listing="$(/usr/bin/security find-identity -v)"
print -r -- "$identity_listing" | /usr/bin/grep -Fq "\"$DEVELOPER_ID_APPLICATION\"" \
    || fail "Developer ID Application identity is not available in the keychain."
print -r -- "$identity_listing" | /usr/bin/grep -Fq "\"$DEVELOPER_ID_INSTALLER\"" \
    || fail "Developer ID Installer identity is not available in the keychain."

/bin/mkdir -p "$output_directory"
output_directory="${output_directory:A}"
temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/jiukong-zhuyin-release.XXXXXX")"
archive_path="$temporary_root/Jiukong Zhuyin.xcarchive"
export_path="$temporary_root/Export"
export_options_path="$temporary_root/ExportOptions.plist"
requirements_path="$temporary_root/InstallerRequirements.plist"
signed_entitlements_path="$temporary_root/SignedEntitlements.plist"
temporary_package="$temporary_root/Jiukong-Zhuyin.pkg"

cleanup() {
    [[ "$temporary_root" == *"/jiukong-zhuyin-release."* ]] \
        && /bin/rm -rf "$temporary_root"
}
trap cleanup EXIT

print "Archiving a universal Developer ID build..."
xcodebuild \
    -quiet \
    -project "$project_path" \
    -scheme "$scheme_name" \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -archivePath "$archive_path" \
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
    CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION" \
    CODE_SIGN_STYLE=Manual \
    PROVISIONING_PROFILE_SPECIFIER="$DEVELOPER_ID_PROVISIONING_PROFILE" \
    JIUKONG_CLOUDKIT_ENTITLEMENTS="$entitlements_path" \
    ENABLE_HARDENED_RUNTIME=YES \
    OTHER_CODE_SIGN_FLAGS="--timestamp" \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    archive

archived_application="$archive_path/Products/Applications/Jiukong Zhuyin.app"
[[ -d "$archived_application" ]] \
    || fail "Archived application was not found at $archived_application"

/usr/libexec/PlistBuddy -c 'Clear dict' "$export_options_path"
/usr/libexec/PlistBuddy -c 'Add :destination string export' "$export_options_path"
/usr/libexec/PlistBuddy -c 'Add :method string developer-id' "$export_options_path"
/usr/libexec/PlistBuddy -c 'Add :signingStyle string manual' "$export_options_path"
/usr/libexec/PlistBuddy -c "Add :signingCertificate string $DEVELOPER_ID_APPLICATION" "$export_options_path"
/usr/libexec/PlistBuddy -c "Add :teamID string $DEVELOPMENT_TEAM" "$export_options_path"
/usr/libexec/PlistBuddy -c 'Add :iCloudContainerEnvironment string Production' "$export_options_path"
/usr/libexec/PlistBuddy -c 'Add :provisioningProfiles dict' "$export_options_path"
/usr/libexec/PlistBuddy \
    -c "Add :provisioningProfiles:$bundle_identifier string $DEVELOPER_ID_PROVISIONING_PROFILE" \
    "$export_options_path"

print "Exporting with production CloudKit entitlements..."
xcodebuild \
    -quiet \
    -exportArchive \
    -archivePath "$archive_path" \
    -exportPath "$export_path" \
    -exportOptionsPlist "$export_options_path"

exported_application="$export_path/Jiukong Zhuyin.app"
[[ -d "$exported_application" ]] \
    || fail "Exported application was not found at $exported_application"

info_plist="$exported_application/Contents/Info.plist"
actual_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist")"
release_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist")"
build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist")"
minimum_system_version="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$info_plist")"

[[ "$actual_identifier" == "$bundle_identifier" ]] \
    || fail "Unexpected bundle identifier: $actual_identifier"
[[ "$release_version" =~ '^[0-9]+([.][0-9]+){2}([-.][A-Za-z0-9.]+)?$' ]] \
    || fail "Bundle version is not a release version: $release_version"
if [[ -n "${RELEASE_TAG:-}" && "$RELEASE_TAG" != "v$release_version" ]]; then
    fail "RELEASE_TAG $RELEASE_TAG does not match bundle version v$release_version."
fi

binary_path="$exported_application/Contents/MacOS/Jiukong Zhuyin"
architectures="$(/usr/bin/lipo -archs "$binary_path")"
for required_architecture in arm64 x86_64; do
    [[ " $architectures " == *" $required_architecture "* ]] \
        || fail "Release binary is missing $required_architecture: $architectures"
done

/usr/bin/codesign --verify --deep --strict --verbose=2 "$exported_application"
signature_details="$(/usr/bin/codesign -d --verbose=4 "$exported_application" 2>&1)"
print -r -- "$signature_details" | /usr/bin/grep -Fq 'Authority=Developer ID Application:' \
    || fail "The exported application is not signed with Developer ID Application."
print -r -- "$signature_details" | /usr/bin/grep -Eq 'flags=.*runtime' \
    || fail "The exported application does not have Hardened Runtime enabled."
[[ -f "$exported_application/Contents/embedded.provisionprofile" ]] \
    || fail "The Developer ID provisioning profile was not embedded."

/usr/bin/codesign \
    --display \
    --entitlements "$signed_entitlements_path" \
    --xml \
    "$exported_application"
signed_container="$(
    /usr/libexec/PlistBuddy \
        -c 'Print :com.apple.developer.icloud-container-identifiers:0' \
        "$signed_entitlements_path"
)"
signed_service="$(
    /usr/libexec/PlistBuddy \
        -c 'Print :com.apple.developer.icloud-services:0' \
        "$signed_entitlements_path"
)"
signed_environment="$(
    /usr/libexec/PlistBuddy \
        -c 'Print :com.apple.developer.icloud-container-environment' \
        "$signed_entitlements_path"
)"
get_task_allow="$(
    /usr/libexec/PlistBuddy \
        -c 'Print :com.apple.security.get-task-allow' \
        "$signed_entitlements_path" \
        2>/dev/null || print false
)"
[[ "$signed_container" == "iCloud.$bundle_identifier" ]] \
    || fail "The signed app has the wrong iCloud container: $signed_container"
[[ "$signed_service" == "CloudKit" ]] \
    || fail "The signed app does not have the CloudKit service entitlement."
[[ "$signed_environment" == "Production" ]] \
    || fail "The signed app does not select the Production CloudKit environment."
[[ "$get_task_allow" != "true" ]] \
    || fail "The signed app contains the forbidden get-task-allow entitlement."

resources_path="$exported_application/Contents/Resources"
for required_resource in \
    LICENSE \
    THIRD_PARTY_NOTICES.md \
    idiomsdict_usage_note.txt \
    reviseddict_usage_note.txt; do
    [[ -f "$resources_path/$required_resource" ]] \
        || fail "Release resource is missing: $required_resource"
done

package_name="Jiukong-Zhuyin-$release_version.pkg"
package_path="$output_directory/$package_name"
checksum_path="$package_path.sha256"
[[ ! -e "$package_path" && ! -e "$checksum_path" ]] \
    || fail "Release output already exists; move it away before rebuilding: $package_path"

/usr/libexec/PlistBuddy -c 'Clear dict' "$requirements_path"
/usr/libexec/PlistBuddy -c 'Add :os array' "$requirements_path"
/usr/libexec/PlistBuddy -c "Add :os:0 string $minimum_system_version" "$requirements_path"
/usr/libexec/PlistBuddy -c 'Add :arch array' "$requirements_path"
/usr/libexec/PlistBuddy -c 'Add :arch:0 string arm64' "$requirements_path"
/usr/libexec/PlistBuddy -c 'Add :arch:1 string x86_64' "$requirements_path"

productbuild_arguments=(
    --product "$requirements_path"
    --identifier "$bundle_identifier.installer"
    --version "$release_version"
    --component "$exported_application" "$installation_directory"
    --sign "$DEVELOPER_ID_INSTALLER"
    --timestamp
)
if [[ -n "${SIGNING_KEYCHAIN:-}" ]]; then
    [[ -f "$SIGNING_KEYCHAIN" ]] || fail "SIGNING_KEYCHAIN does not exist: $SIGNING_KEYCHAIN"
    productbuild_arguments+=(--keychain "$SIGNING_KEYCHAIN")
fi

print "Creating signed installer package..."
/usr/bin/productbuild "${productbuild_arguments[@]}" "$temporary_package"
/usr/sbin/pkgutil --check-signature "$temporary_package"

print "Submitting installer package to Apple's notary service..."
xcrun notarytool submit \
    "$temporary_package" \
    "${notary_authentication[@]}" \
    --wait \
    --timeout 60m

print "Stapling and validating the notarization ticket..."
xcrun stapler staple "$temporary_package"
xcrun stapler validate "$temporary_package"
/usr/sbin/spctl --assess --type install --verbose=2 "$temporary_package"

/bin/mv "$temporary_package" "$package_path"
(
    cd "$output_directory"
    /usr/bin/shasum -a 256 "$package_name" > "$package_name.sha256"
)

print "Release package is ready:"
print "  $package_path"
print "  $checksum_path"
print "  Version: $release_version ($build_number)"
print "  Architectures: $architectures"
print "  Installs to: $installation_directory/Jiukong Zhuyin.app"
