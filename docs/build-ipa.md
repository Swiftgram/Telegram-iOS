# Building an IPA

There are two ways to get an installable `.ipa` out of this fork: the GitHub Actions
workflow (`.github/workflows/build.yml`) or a local macOS build with `Make.py`.

## GitHub Actions: "Build unsigned IPA"

The workflow is manual:

1. Push the repository to GitHub (see the root README / the tweak handoff notes).
2. Open **Actions → Build unsigned IPA → Run workflow**.
3. Inputs:
   - **runner** — the runner label. Default `macos-26`; use `macos-15`, `macos-14` or
     `self-hosted` when needed.
   - **xcode** — an installed Xcode version such as `27.1`. Empty selects the newest
     installed Xcode.
   - **release** — also publish `Swiftgram.ipa` and its dSYMs as a GitHub Release
     (`build-<run number>`).
4. When the job finishes, download the **Swiftgram-unsigned-ipa** artifact (contains
   `Swiftgram.ipa` and `Swiftgram.DSYMs.zip`), or open the created Release.

Pushing a tag that starts with `build-` (for example `build-20261108-1200`) also runs the
workflow and publishes the IPA as a GitHub Release with that tag, so the whole chain can be
automated: `git push` + `git push <tag>` → build → release.

What it does: checks out the repo with submodules, imports the fake codesigning
certificates from `build-system/fake-codesigning`, builds
`--configuration=release_arm64` with `build-system/appstore-configuration.json`, and copies
the result with `--outputBuildArtifactsPath=build/artifacts`.

### Requirements and real limits

- **Xcode 27.1 and the iOS 27 SDK.** `versions.json` pins them; the workflow passes
  `--overrideXcodeVersion`, so an older Xcode is used if 27.1 is missing, but the source may
  not compile against an older SDK. GitHub-hosted runners only carry the Xcode versions
  Apple publishes on their images — a self-hosted Mac is the reliable option.
- **Disk.** A cold Telegram/Swiftgram Bazel build plus the Bazel output base needs roughly
  30–40 GB. The workflow deletes unused Xcode copies and simulator runtimes, which buys
  about 10–20 GB on a hosted runner.
- **Time.** A cold build on a 3-vCPU hosted runner takes hours; GitHub's job limit is
  6 hours. Self-hosted hardware is much faster, and a Bazel cache helps a lot:
  `--cacheHost=grpc://your-cache:9092` (see `build-system/Make/Make.py`) or
  `--cacheDir=~/telegram-bazel-cache` for a local disk cache.
- **Minutes.** macOS runner minutes are billed with a multiplier (10x on the free plan),
  so a multi-hour hosted build can exhaust a free quota in one run.
- **Submodules.** The checkout uses `submodules: recursive`; the webrtc/tgcalls/td
  submodules are large and the first checkout takes a while.

### Signing

The workflow produces an **unsigned** IPA, exactly like the old CI: fake certificates are
imported only so Bazel can run codesign steps. An unsigned IPA does not install on a
stock iPhone by itself — use Sideloadly/AltStore (re-signs with your Apple ID, 7-day
certificate), TrollStore where supported, or sign it with your own certificate.

For a properly signed build, replace the fake-signing arguments with fastlane-match:

```sh
python3 -u build-system/Make/Make.py \
  build \
  --configurationPath=build-system/appstore-configuration.json \
  --gitCodesigningRepository=git@github.com:<you>/certificates.git \
  --gitCodesigningType=development \
  --gitCodesigningUseCurrent \
  --configuration=release_arm64 \
  --buildNumber="$BUILD_NUMBER" \
  --outputBuildArtifactsPath=build/artifacts
```

and provide the variables that path expects (`TELEGRAM_CODESIGNING_GIT_PASSWORD`, the
matching provisioning profiles and certificate repository). Keep those in GitHub Secrets,
never in the repository.

### API credentials

`build-system/appstore-configuration.json` currently carries the upstream Telegram
`api_id`/`api_hash` and App Store ids. For a personal fork replace `api_id`, `api_hash`,
`bundle_id` and `team_id` with your own values (api credentials come from
<https://my.telegram.org>), and consider `"is_appstore_build": "false"` for local use.

## Local macOS build

```sh
python3 build-system/Make/ImportCertificates.py --path build-system/fake-codesigning/certs
python3 -u build-system/Make/Make.py \
  --overrideXcodeVersion \
  --bazelUserRoot="$HOME/bazel-root" \
  build \
  --configurationPath=build-system/appstore-configuration.json \
  --codesigningInformationPath=build-system/fake-codesigning \
  --configuration=release_arm64 \
  --buildNumber=1 \
  --outputBuildArtifactsPath=build/artifacts
```

The result is `build/artifacts/Swiftgram.ipa` plus `Swiftgram.DSYMs.zip`.

## GitLab CI alternative

`.gitlab-ci.yml` already has `vm-build` jobs that run in ephemeral macOS VMs (tart) on a
Mac runner host and publish `build/artifacts`. That is the path upstream uses for signed
builds and is a good fit if you have a Mac to host the runner.
