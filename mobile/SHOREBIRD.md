# Shorebird Code Push — Release & Patch Guide

Shorebird ships **Dart-only** code changes over-the-air ("patches") so users get
fixes on their next app launch **without** downloading a new APK. It sits on top
of the existing GitHub-release update flow — it does not replace it.

## What can and cannot be patched OTA

| Change | Ship via |
| --- | --- |
| Dart code (UI, logic, bug fixes, the warehouse shift feature, etc.) | **Patch** (OTA) |
| New/updated pub package with native code, Android/Gradle/manifest changes | **Full release** (new APK) |
| Assets bundled in the APK, Flutter/Dart SDK upgrade, app icon | **Full release** |
| Anything that changes `version:` major/minor/patch on its own | **Full release** |

Rule of thumb: if `flutter build apk` would produce different *native* output, you
need a full release. Otherwise a patch works.

## One-time setup (you must run these — they need your Shorebird account)

```bash
# 1. Install the CLI (Windows PowerShell)
iwr -UseBasicParsing https://raw.githubusercontent.com/shorebirdtech/install/main/install.ps1 | iex

# 2. Log in (opens a browser)
shorebird login

# 3. From the mobile/ directory, create the app + real app_id.
#    This overwrites the placeholder in shorebird.yaml.
cd mobile
shorebird init

# 4. (For CI) create a machine token and add it as the SHOREBIRD_TOKEN
#    GitHub Actions secret.
shorebird login:ci
```

After `shorebird init`, confirm `mobile/shorebird.yaml` has a real `app_id`
(not `REPLACE_WITH_shorebird_init`). The `shorebird.yaml` is already wired into
`pubspec.yaml` assets.

## Day-to-day: shipping a Dart-only fix (the common case)

```bash
cd mobile
# Build/test as usual, then patch the release your users are currently on:
shorebird patch android --release-version 1.4.0+10
```

- `--release-version` must match a release you previously cut with
  `shorebird release` (see below). Users on that release get the patch on next
  launch. **Do not** create a GitHub release for a patch — the in-app update
  dialog should stay silent.
- The app version (`package_info` / pubspec `version:`) does **not** change with
  a patch, so `version_check_service.dart` will not nag users — exactly what we
  want.

## Cutting a full release (baseline / native changes)

A "release" is the installable APK that patches attach to. You need a fresh
release whenever you make a non-patchable change, **and** for the very first
Shorebird build.

```bash
cd mobile
# Bump version: in pubspec.yaml first (e.g. 1.4.1+11), then:
shorebird release android --artifact apk
```

Then publish it the way the app's updater expects:

1. Create a GitHub release with tag **`v1.4.1`** (semver only — a `+` in the tag
   404s the release page; see project memory) and attach the APK.
2. The [github-webhook](../server/src/routes/app.js) refreshes `/app/version`
   and pushes "New Update Available" to all devices.
3. Users on older versions download & install the new APK via the in-app dialog.

> Important: build releases with `shorebird release`, **never** plain
> `flutter build apk`. An APK built without Shorebird cannot receive patches.

## How this coexists with the existing updater

- **Patch** → no GitHub release → `/app/version` unchanged → no update dialog →
  silent OTA update. Use for Dart fixes.
- **Release** → new GitHub release → `/app/version` advertises it → update dialog
  prompts a full reinstall. Use for native/version changes and new installs.

No changes were needed in `version_check_service.dart`: patches are intentionally
invisible to it, and releases flow through the existing version check unchanged.

## CI

`.github/workflows/shorebird.yml` runs either path on manual dispatch
(Actions → Shorebird → Run workflow → choose `patch` or `release`). It needs the
`SHOREBIRD_TOKEN` secret. Verify the APK output path in the "Publish GitHub
release" step on your first run.

## Verifying a patch landed

Optional: add the `shorebird_code_push` package to read the current patch number
in-app (e.g. show it on the Settings/About screen) so you can confirm a patch
applied. Not required for patches to work. Ask and I'll wire it in.
