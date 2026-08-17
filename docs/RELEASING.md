# Releasing Schiera

Schiera's release workflow builds a universal `arm64`/`x86_64` application, packages it in a compressed DMG, creates a SHA-256 checksum, and stores both files as GitHub Actions artifacts. A pushed `v*` tag publishes the files in GitHub Releases. A manual workflow run can either keep them as temporary artifacts or publish a release.

## Release modes

The workflow selects exactly one mode:

- **Ad-hoc preview:** used when none of the Apple secrets exist. The release is marked as a prerelease and its filename ends in `-unsigned.dmg`. Gatekeeper may require explicit user approval before the first launch.
- **Developer ID:** used when every Apple secret below exists. The app is signed with a Developer ID Application certificate, the DMG is submitted with `notarytool`, and Apple's ticket is stapled before publication.

A partially configured signing environment fails instead of silently publishing an unnotarized release.
The Release build explicitly disables Xcode's development entitlement injection so `get-task-allow` cannot enter a notarization submission.

## Required GitHub Actions secrets

Configure these in **Repository Settings → Secrets and variables → Actions**:

| Secret | Contents |
| --- | --- |
| `MACOS_CERTIFICATE_BASE64` | Base64-encoded `.p12` containing a Developer ID Application certificate and private key. |
| `MACOS_CERTIFICATE_PASSWORD` | Password used when exporting the `.p12`. |
| `APPLE_TEAM_ID` | Apple Developer team identifier. |
| `APPLE_API_KEY_P8_BASE64` | Base64-encoded App Store Connect API `.p8` private key authorized for notarization. |
| `APPLE_API_KEY_ID` | App Store Connect API key identifier. |
| `APPLE_API_ISSUER_ID` | App Store Connect API issuer identifier. |

Never commit certificates, private keys, passwords, or account identifiers. Repository scans deliberately reject common signing and credential material.

## Publish from a tag

After the intended commit is on `main`:

```sh
git tag -a v0.1.0 -m "Schiera 0.1.0"
git push origin v0.1.0
```

The tag starts `.github/workflows/release.yml`. Successful output appears on the repository's Releases page and remains available as a workflow artifact for 30 days.

## Manual packaging

Run **Release DMG** from the GitHub Actions interface, enter a semantic version, and leave **Publish** disabled to test packaging without creating a release. Enabling **Publish** creates the matching tag and release at the workflow commit.

The low-level DMG helper can also package an existing local app:

```sh
./scripts/package-dmg.sh /path/to/Schiera.app dist/Schiera.dmg "Schiera"
```

Local packaging does not sign or notarize the app. Signing is handled only by the release workflow when the complete secret set is present.
