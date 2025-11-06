# SWORDCOMM CI/CD Guide

This guide explains how to use the automated build and deployment workflows for SWORDCOMM.

---

## Overview

SWORDCOMM has **two main workflows**:

1. **`ios-build.yml`** - Builds frameworks and models (runs on every push)
2. **`deployment.yml`** - Deploys to Signal-iOS and TestFlight (runs on main/develop or manually)

---

## Workflow 1: iOS Build (Automatic)

**File**: `.github/workflows/ios-build.yml`

### When It Runs

- ✅ Every push to `main`, `develop`, or `claude/**` branches
- ✅ Every pull request to `main` or `develop`
- ✅ Manual trigger (workflow_dispatch)

### What It Does

1. **Builds liboqs XCFramework** (~5 min)
   - Downloads liboqs source
   - Builds for iOS device (arm64)
   - Builds for iOS Simulator (arm64 + x86_64)
   - Creates universal XCFramework (~2 MB)

2. **Converts Translation Model** (~10 min)
   - Downloads OPUS-MT from Hugging Face
   - Converts to CoreML
   - Applies INT8 quantization (310MB → 78MB)
   - Validates with test translations

3. **Builds iOS Project** (Debug + Release)
   - Configures CMake for iOS
   - Builds SWORDCOMM frameworks
   - Runs tests

4. **Verifies Integration**
   - Checks all files exist
   - Validates documentation
   - Checks for old EMMA references

5. **Creates Release Package** (on main/develop)
   - Bundles source + artifacts
   - 30-day retention

### Artifacts Produced

| Artifact | Size | Retention | Description |
|----------|------|-----------|-------------|
| `liboqs-xcframework` | ~2 MB | 7 days | Production cryptography |
| `translation-model` | ~78 MB | 7 days | CoreML translation model |
| `swordcomm-Debug-artifacts` | Varies | 7 days | Debug build outputs |
| `swordcomm-Release-artifacts` | Varies | 7 days | Release build outputs |
| `swordcomm-release-package` | ~80 MB | 30 days | Complete deployment package |

### How to Use

**Option 1: Download from GitHub Actions**

1. Go to **Actions** tab in GitHub
2. Click on latest workflow run
3. Scroll to **Artifacts** section
4. Download `swordcomm-release-package`
5. Extract and use in Signal-iOS integration

**Option 2: Clone and Build Locally**

```bash
git clone https://github.com/SWORDIntel/Swordcomm-IOS.git
cd Swordcomm-IOS

# Frameworks are automatically built on push
# Or trigger manually:
# Actions → SWORDCOMM iOS Build → Run workflow
```

---

## Workflow 2: Deployment (Manual/Automatic)

**File**: `.github/workflows/deployment.yml`

### When It Runs

- ✅ After successful iOS build (on `main` or `develop`)
- ✅ Manual trigger with options

### What It Does

1. **Prepares Deployment**
   - Generates version number
   - Downloads build artifacts
   - Verifies everything is ready

2. **Integrates into Signal-iOS**
   - Clones Signal-iOS repository
   - Copies SWORDCOMM code and artifacts
   - Runs integration script
   - Installs CocoaPods
   - Creates integration branch
   - Optionally creates PR

3. **Builds for TestFlight** (optional)
   - Imports signing certificate
   - Installs provisioning profile
   - Archives for App Store
   - Exports IPA
   - Uploads to TestFlight

4. **Creates GitHub Release** (on main)
   - Generates changelog
   - Creates versioned release
   - Uploads all artifacts
   - Includes complete documentation

5. **Sends Notifications** (if configured)
   - Slack notifications
   - Deployment summary

### Deployment Types

#### 1. Integration Only (Default)

Integrates SWORDCOMM into Signal-iOS without building IPA.

```bash
# Automatic after build
# Or manual trigger:
Actions → SWORDCOMM Deployment → Run workflow
  Deployment type: integration-only
```

**Produces:**
- Integrated Signal-iOS repository
- Integration branch
- Optional PR to Signal-iOS

#### 2. TestFlight Build

Builds and uploads to TestFlight (requires secrets configured).

```bash
Actions → SWORDCOMM Deployment → Run workflow
  Deployment type: testflight
```

**Produces:**
- Integrated Signal-iOS
- Signed IPA
- TestFlight upload

#### 3. Full Release

Complete release with GitHub Release and TestFlight.

```bash
Actions → SWORDCOMM Deployment → Run workflow
  Deployment type: full-release
```

**Produces:**
- GitHub Release with changelog
- TestFlight build
- Complete artifacts package

### Required Secrets

For TestFlight deployment, configure these secrets in GitHub Settings:

| Secret | Description | How to Get |
|--------|-------------|------------|
| `IOS_CERTIFICATE_P12` | iOS Distribution Certificate (base64) | Export from Keychain, encode: `base64 cert.p12` |
| `IOS_CERTIFICATE_PASSWORD` | Certificate password | Password used when exporting certificate |
| `IOS_PROVISIONING_PROFILE` | Provisioning Profile (base64) | Download from Apple Developer, encode: `base64 profile.mobileprovision` |
| `CODE_SIGN_IDENTITY` | Code signing identity | Usually: `iPhone Distribution: Your Name (TEAMID)` |
| `PROVISIONING_PROFILE_SPECIFIER` | Profile name | Name from Apple Developer portal |
| `DEVELOPMENT_TEAM` | Team ID | 10-character team ID from Apple |
| `APP_STORE_CONNECT_API_KEY` | App Store Connect API Key | Create in App Store Connect → Users & Access → Keys |
| `APP_STORE_CONNECT_ISSUER_ID` | API Issuer ID | Found with API key in App Store Connect |

**Optional:**
| Secret | Description |
|--------|-------------|
| `SIGNAL_REPO_TOKEN` | GitHub token with write access to Signal-iOS fork |
| `SLACK_WEBHOOK_URL` | Slack webhook for notifications |

### Configuring Secrets

```bash
# In your GitHub repository:
Settings → Secrets and variables → Actions → New repository secret

# Example for certificate:
base64 -i your-cert.p12 | pbcopy
# Paste into IOS_CERTIFICATE_P12

# Example for provisioning profile:
base64 -i your-profile.mobileprovision | pbcopy
# Paste into IOS_PROVISIONING_PROFILE
```

---

## Manual Deployment Workflow

### Step 1: Trigger Build

1. Go to **Actions** tab
2. Click **SWORDCOMM iOS Build**
3. Click **Run workflow**
4. Select branch (usually `main` or `develop`)
5. Click **Run workflow**

**Wait ~20-30 minutes for build to complete**

### Step 2: Deploy

Once build succeeds:

1. Go to **Actions** tab
2. Click **SWORDCOMM Deployment**
3. Click **Run workflow**
4. Choose deployment type:
   - **integration-only**: Just integrate into Signal-iOS
   - **testflight**: Build and upload to TestFlight
   - **full-release**: Create GitHub Release + TestFlight
5. (Optional) Change Signal repository if using a fork
6. (Optional) Enable "Create PR" to auto-create PR
7. Click **Run workflow**

**Wait ~15-45 minutes depending on deployment type**

### Step 3: Verify

1. Check **Summary** at bottom of workflow run
2. Download artifacts if needed
3. Review integration PR if created
4. Check TestFlight if uploaded

---

## Automatic Deployment (Recommended)

For continuous deployment, the workflow runs automatically:

```
Developer → Push to main/develop
          ↓
    iOS Build Workflow (~20 min)
          ↓
    Deployment Workflow (~15 min)
          ↓
    GitHub Release + Artifacts
```

**No manual intervention needed!**

---

## Artifacts and Downloads

### From GitHub Actions

All artifacts are available in the workflow run:

1. Go to completed workflow run
2. Scroll to **Artifacts** section
3. Click artifact name to download

### From GitHub Releases

For tagged releases:

1. Go to **Releases** page
2. Find latest release
3. Download assets:
   - `swordcomm-vX.X.X.tar.gz` - Complete package
   - `Signal-SWORDCOMM.ipa` - iOS app (if built)

---

## Local Development

### Build Frameworks Locally (macOS only)

```bash
# Build liboqs
./SWORDCOMM/Scripts/build_liboqs.sh --minimal --clean

# Convert translation model
python3 SWORDCOMM/Scripts/convert_translation_model.py --quantize

# Output:
# - SWORDCOMM/Frameworks/liboqs.xcframework
# - SWORDCOMM/TranslationKit/Models/*.mlmodel
```

### Integrate into Signal-iOS Locally

```bash
# Clone Signal-iOS
git clone https://github.com/signalapp/Signal-iOS.git
cd Signal-iOS

# Copy SWORDCOMM
cp -R /path/to/Swordcomm-IOS/SWORDCOMM .

# Run integration script
./SWORDCOMM/Scripts/integrate_swordcomm.sh

# Install pods
pod install

# Open in Xcode
open Signal.xcworkspace
```

---

## Troubleshooting

### Build Fails: "CMake not found"

**Solution**: macOS runners have CMake pre-installed. If running locally:
```bash
brew install cmake
```

### Deployment Fails: "Permission denied"

**Solution**: Check that `SIGNAL_REPO_TOKEN` has write access to Signal-iOS repository.

### TestFlight Upload Fails: "Invalid certificate"

**Solution**:
1. Verify certificate is valid: `security find-identity -p codesigning`
2. Ensure certificate is base64 encoded correctly
3. Check certificate password is correct

### "No artifacts found"

**Solution**: Wait for iOS Build workflow to complete successfully before triggering deployment.

### Integration PR Not Created

**Possible reasons**:
1. `create_pr` input not set to `true`
2. `SIGNAL_REPO_TOKEN` not configured
3. Branch already exists
4. No changes to commit

---

## Monitoring Builds

### Slack Notifications

Configure Slack webhook for notifications:

1. Create Slack app with Incoming Webhook
2. Copy webhook URL
3. Add as secret: `SLACK_WEBHOOK_URL`

Notifications include:
- Deployment status
- Version and build number
- Integration and TestFlight results
- Link to workflow run

### Email Notifications

GitHub sends emails automatically for:
- Workflow failures
- Required approvals
- Deployment completions

Configure in: Settings → Notifications

---

## Best Practices

### 1. Use Branches

- `main` - Production releases
- `develop` - Development builds
- `claude/**` - Feature branches

### 2. Tag Releases

```bash
git tag -a v1.0.0 -m "Release v1.0.0"
git push origin v1.0.0
```

Creates versioned GitHub Release automatically.

### 3. Review Before Merge

Always review integration PR before merging to Signal-iOS main branch.

### 4. Test TestFlight Builds

Test every TestFlight build on device before releasing to users.

### 5. Keep Secrets Updated

Rotate certificates and keys regularly. Update secrets when:
- Certificates expire
- Team changes
- Security incidents

---

## Workflow Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Developer Push                                              │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│ iOS Build Workflow                                          │
│ ┌─────────────────┐ ┌─────────────────┐ ┌──────────────┐   │
│ │ Build liboqs    │ │ Convert Model   │ │ Build iOS    │   │
│ │ (~5 min)        │ │ (~10 min)       │ │ (~5 min)     │   │
│ └────────┬────────┘ └────────┬────────┘ └──────┬───────┘   │
│          │                   │                  │            │
│          └───────────────────┴──────────────────┘            │
│                              │                               │
│                    ┌─────────▼──────────┐                    │
│                    │ Upload Artifacts   │                    │
│                    └─────────┬──────────┘                    │
└──────────────────────────────┼───────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│ Deployment Workflow (triggered on success)                  │
│ ┌──────────────────┐                                        │
│ │ Prepare Deploy   │                                        │
│ └────────┬─────────┘                                        │
│          │                                                   │
│    ┌─────▼─────┬───────────┬────────────┐                  │
│    │           │           │            │                   │
│ ┌──▼────────┐ ┌▼────────┐ ┌▼─────────┐ ┌▼──────────┐      │
│ │ Integrate │ │TestFlight│ │ GitHub   │ │ Notify    │      │
│ │ Signal    │ │ Build    │ │ Release  │ │           │      │
│ │ (~5 min)  │ │ (~15 min)│ │ (~2 min) │ │ (~1 min)  │      │
│ └───────────┘ └──────────┘ └──────────┘ └───────────┘      │
└─────────────────────────────────────────────────────────────┘
                               │
                               ▼
                    ┌──────────────────────┐
                    │ Artifacts & Release  │
                    │ - GitHub Release     │
                    │ - TestFlight Build   │
                    │ - Integrated Signal  │
                    └──────────────────────┘
```

---

## Support

For issues with workflows:
1. Check workflow logs in GitHub Actions
2. Review this guide
3. Check required secrets are configured
4. Open issue in repository

---

**Last Updated**: 2025-11-06
**Workflows Version**: 1.0
