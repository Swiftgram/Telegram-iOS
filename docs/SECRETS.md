# GitHub Actions secrets

Add these under **Settings → Secrets and variables → Actions → New repository secret**, or with the GitHub CLI
(`gh secret set NAME < file` reads the value from a file so it stays out of your shell history). Never commit the
values or paste them into an issue or chat.

| Secret | Needed for | Value |
| --- | --- | --- |
| `TG_API_ID` | login in the built app | the numeric `api_id` of your application at <https://my.telegram.org/apps> (platform "other") |
| `TG_API_HASH` | login in the built app | its 32-character `api_hash` |
| `P12_BASE64` | signing (optional) | signing certificate `.p12`, base64: `base64 -i cert.p12 \| pbcopy` |
| `P12_PASSWORD` | signing (optional) | the `.p12` password |
| `MOBILEPROVISION_BASE64` | signing (optional) | provisioning profile, base64: `base64 -i profile.mobileprovision \| pbcopy` |

`TG_API_ID` and `TG_API_HASH` are checked by `build-ipa.yml` before the build (digits only, 32 hex characters) and
written into the build configuration on the runner only. Without them the build keeps Telegram's own `api_id` 8,
and no login code is delivered to it, neither by SMS nor in the app. Without the signing secrets the IPA is
published unsigned and has to be signed on your side (for example when sideloading).

To trigger a build after adding them: **Actions → Build and Release TrollGram IPA → Run workflow**.
