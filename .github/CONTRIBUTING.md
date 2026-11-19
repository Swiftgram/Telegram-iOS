# Contributing to TrollGram

Thanks for considering a contribution. TrollGram is a relatively small
set of project-specific changes on top of a large upstream iOS codebase,
so focused and well-documented changes are much easier to review than
broad refactors.

This guide describes the preferred contribution process. It is
intentionally practical: if a rule does not fit your change, explain the
reason in the pull request.

## Before you start

1.  Read the [README](README.md) to understand the project and its
    current limitations.
2.  Search [open and closed
    issues](https://github.com/vnikolas2009/TrollGram/issues) before
    reporting or implementing a bug.
3.  For a substantial change, open an issue first and describe the
    problem and the proposed direction. This helps avoid work on a
    feature that does not fit the project.
4.  Do not start from an old fork of the repository unless you have
    checked that it is up to date with the current default branch.

Small documentation fixes and clearly scoped bug fixes do not need prior
discussion.

## What contributions are useful?

Examples include:

-   Reproducible fixes for TrollGram-specific bugs.
-   Improvements to the privacy settings or their runtime integration.
-   Fixes to the Python plugin host and compatibility layer.
-   Clear documentation, translations and build instructions.
-   Tests or diagnostics that make regressions easier to identify.
-   Build workflow improvements that do not expose credentials or weaken
    repository security.

Please avoid submitting unrelated formatting changes across upstream
files. Keep the diff as small as the task allows.

## Development setup

Use the toolchain versions listed in [`versions.json`](versions.json).
The build uses macOS, Xcode, Python and Bazel.

``` bash
git clone --recursive https://github.com/vnikolas2009/TrollGram.git
cd TrollGram
python3 build-system/setup_python.py
```

If submodules were not downloaded:

``` bash
git submodule update --init --recursive
```

The current unsigned release build command is documented in the
[README](README.md). A successful build is useful, but it does not
replace testing the actual behaviour on a device.

## Branches and commits

-   Create a separate branch for each change.
-   Keep each pull request focused on one issue or closely related set
    of changes.
-   Use descriptive commit messages, for example:
    -   `Fix plugin import error handling`
    -   `Document privacy flag behaviour`
    -   `Prevent duplicate message archive entries`
-   Avoid committing generated build output, local caches, certificates,
    provisioning profiles, IPA files, personal logs or credentials.
-   Do not reformat large upstream files just to match personal style
    preferences.

## Code expectations

### Swift

-   Follow the conventions of the surrounding source file.
-   Prefer the smallest safe change over a broad rewrite.
-   Keep privacy-related state and network behaviour explicit.
-   Avoid introducing new dependencies unless they are necessary and
    their licence is compatible with the project.
-   Do not silently change existing defaults or user data formats.

### Python plugins

-   Keep the compatibility layer predictable and document unsupported
    APIs.
-   Handle invalid plugin files and runtime exceptions without crashing
    the whole app.
-   Do not assume that Android-only exteraGram APIs exist on iOS.
-   Avoid network access or file operations unless they are required and
    clearly documented.
-   Never include a plugin that collects credentials, session files or
    private messages.

### Privacy and message handling

Changes to read receipts, presence, message archiving, protected content
or view-once media need extra care.

A pull request in this area should explain:

1.  Which Telegram client request, event or local behaviour is affected.
2.  Which chat types and message types were tested.
3.  What remains unaffected or unsupported.
4.  Whether the change can cause messages or metadata to be stored
    locally.
5.  Any limitations caused by server-side behaviour or other clients.

Do not describe a client-side change as an absolute privacy guarantee.

## Testing

There is no single test command that covers every feature in this fork.
At minimum:

-   Build the affected target or the full app when practical.
-   Test the changed behaviour on a real device or a clearly identified
    simulator configuration.
-   For plugin changes, test a valid plugin, an invalid plugin and a
    plugin that raises an exception.
-   For archive changes, test duplicate events, edited messages and
    deleted messages where applicable.
-   For settings changes, test enabling, disabling and relaunching the
    app.
-   Include the exact Xcode version, iOS version, device model and build
    configuration in the pull request.

If you cannot run a full build, say so. Do not report an untested change
as verified.

## Pull request checklist

Before submitting, check that:

-   [ ] The change addresses one clear problem.
-   [ ] The diff contains no unrelated generated files or formatting
    noise.
-   [ ] No secrets, credentials, session data or personal information
    are included.
-   [ ] Documentation is updated when behaviour or setup changes.
-   [ ] Relevant tests or manual checks have been performed.
-   [ ] Limitations and untested cases are listed honestly.
-   [ ] Upstream and third-party copyright/licence notices are
    preserved.

A useful pull request description includes **Context**, **What
changed**, **How it was tested**, and **Known limitations**.

## Bug reports

Open an issue with:

-   A short, specific title.
-   The expected result and the actual result.
-   Steps to reproduce the problem.
-   Device model and iOS version.
-   TrollGram version or commit hash.
-   Xcode version and build configuration, if the issue is
    build-related.
-   A relevant log excerpt or screenshot, with personal information
    removed.

Check that the issue does not already exist. Do not upload account
sessions, API hashes, phone numbers, private chats or complete
application archives.

## Security reports

Please do not publish a working exploit or sensitive vulnerability
details in a public issue. Contact the maintainer privately using a
contact method published by the repository owner. Include enough
information to reproduce the issue safely.

## Review and maintenance

A pull request may be revised, delayed or closed if it is out of scope,
cannot be reproduced, changes upstream code unnecessarily, or lacks
enough information to review. Opening a pull request does not guarantee
that it will be merged.

Thanks for helping make TrollGram easier to understand, build and
maintain.
