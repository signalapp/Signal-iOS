# Signal-iOS Build Configuration for SWORDCOMM

**Phase**: 4 - Signal Integration
**Date**: 2025-11-06

---

## Overview

This document describes the build configuration changes needed to integrate SWORDCOMM into Signal-iOS.

---

## Xcode Project Configuration

### 1. Targets

SWORDCOMM consists of multiple components that need to be linked:

| Component | Type | Purpose |
|-----------|------|---------|
| **Signal** | App Target | Main Signal app (includes SWORDCOMM integration) |
| **SWORDCOMMSecurityKit** | Framework | Security features (via CocoaPods) |
| **SWORDCOMMTranslationKit** | Framework | Translation features (via CocoaPods) |

### 2. Build Settings

#### Signal App Target

**Swift Compiler - General**:
- **Objective-C Bridging Header**: `$(PROJECT_DIR)/SWORDCOMM/SWORDCOMM-Bridging-Header.h`
- **Swift Language Version**: Swift 5

**Apple Clang - Language - C++**:
- **C++ Language Dialect**: GNU++17 (`-std=gnu++17`)
- **C++ Standard Library**: libc++ (automatic on iOS)

**Preprocessor Macros** (optional, for production crypto):
```
HAVE_LIBOQS=1    // Enable when liboqs is integrated
```

**Header Search Paths**:
```
$(inherited)
$(PROJECT_DIR)/SWORDCOMM/SecurityKit/Native
$(PROJECT_DIR)/SWORDCOMM/SecurityKit/Bridge
$(PROJECT_DIR)/SWORDCOMM/TranslationKit/Native
$(PROJECT_DIR)/SWORDCOMM/TranslationKit/Bridge
```

**Framework Search Paths**:
```
$(inherited)
$(PODS_CONFIGURATION_BUILD_DIR)/SWORDCOMMSecurityKit
$(PODS_CONFIGURATION_BUILD_DIR)/SWORDCOMMTranslationKit
```

**Runpath Search Paths**:
```
$(inherited)
@executable_path/Frameworks
@loader_path/Frameworks
```

#### Build Phases

**1. Run Script - Build SWORDCOMM Native Code** (Optional, if building from source):
```bash
#!/bin/bash
# Build SWORDCOMM native libraries
cd "${PROJECT_DIR}/SWORDCOMM"
if [ -f "CMakeLists.txt" ]; then
    mkdir -p build
    cd build
    cmake .. -DCMAKE_BUILD_TYPE=Release
    cmake --build . --parallel
fi
```

**2. Compile Sources**:
- Include all `.swift` files from Signal
- Include SWORDCOMM integration extensions:
  - `SignalAppDelegate+SWORDCOMM.swift`
  - `SignalSettingsViewController+SWORDCOMM.swift`
  - `SignalConversationViewController+SWORDCOMM.swift`
  - `SignalMessageTranslation+SWORDCOMM.swift`

**3. Link Binary With Libraries**:
- `SWORDCOMMSecurityKit.framework` (via CocoaPods)
- `SWORDCOMMTranslationKit.framework` (via CocoaPods)
- `Foundation.framework`
- `Security.framework`
- `UIKit.framework`
- `SwiftUI.framework`
- `liboqs.xcframework` (when integrated)

---

## Podfile Configuration

### Current Configuration

```ruby
platform :ios, '15.0'

use_frameworks!

target 'Signal' do
  # Signal dependencies
  pod 'SignalServiceKit', path: './SignalServiceKit'
  pod 'SignalUI', path: './SignalUI'
  # ... other Signal pods ...

  # ┌──────────────────────────────────┐
  # │ SWORDCOMM Integration                  │
  # └──────────────────────────────────┘
  pod 'SWORDCOMMSecurityKit', :path => './SWORDCOMM'
  pod 'SWORDCOMMTranslationKit', :path => './SWORDCOMM'

end

target 'SignalTests' do
  # Test pods
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      # Enable C++17 for SWORDCOMM
      if target.name.start_with?('SWORDCOMM')
        config.build_settings['CLANG_CXX_LANGUAGE_STANDARD'] = 'gnu++17'
        config.build_settings['CLANG_CXX_LIBRARY'] = 'libc++'
      end
    end
  end
end
```

### Installation

```bash
pod install
```

After installation, always open `Signal.xcworkspace`, not `Signal.xcodeproj`.

---

## CMake Configuration

### SWORDCOMM/CMakeLists.txt

The SWORDCOMM native code uses CMake for cross-platform builds:

```cmake
cmake_minimum_required(VERSION 3.22.1)
project(SWORDCOMM_SecurityKit)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# iOS-specific settings
set(CMAKE_OSX_DEPLOYMENT_TARGET "15.0")
set(CMAKE_OSX_ARCHITECTURES "arm64")

# Source files
set(SECURITY_SOURCES
    SecurityKit/Native/el2_detector.cpp
    SecurityKit/Native/performance_counters.cpp
    SecurityKit/Native/cache_operations.cpp
    SecurityKit/Native/memory_scrambler.cpp
    SecurityKit/Native/timing_obfuscation.cpp
    SecurityKit/Native/nist_pqc.cpp
    SecurityKit/Native/liboqs_wrapper.cpp
    SecurityKit/Native/hkdf.cpp
)

# Create library
add_library(SWORDCOMMSecurityKit STATIC ${SECURITY_SOURCES})

# Include directories
target_include_directories(SWORDCOMMSecurityKit PUBLIC
    SecurityKit/Native
    SecurityKit/Bridge
    Common
)

# Link iOS frameworks
find_library(FOUNDATION_FRAMEWORK Foundation REQUIRED)
find_library(SECURITY_FRAMEWORK Security REQUIRED)

target_link_libraries(SWORDCOMMSecurityKit
    ${FOUNDATION_FRAMEWORK}
    ${SECURITY_FRAMEWORK}
)
```

### Building with CMake (Optional)

```bash
cd SWORDCOMM
mkdir build
cd build

cmake .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0

cmake --build . --parallel
```

---

## Info.plist Configuration

### Add SWORDCOMM Metadata

**Signal/Info.plist**:

```xml
<key>SWORDCOMMVersion</key>
<string>1.3.0</string>

<key>SWORDCOMMEnabled</key>
<true/>

<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <false/>
    <!-- SWORDCOMM translation network fallback uses HTTPS only -->
</dict>
```

---

## Entitlements

### Required Capabilities

**Signal.entitlements**:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Existing Signal entitlements -->
    <key>keychain-access-groups</key>
    <array>
        <string>$(AppIdentifierPrefix)org.whispersystems.signal</string>
    </array>

    <!-- SWORDCOMM uses Keychain for secure key storage -->
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.org.whispersystems.signal</string>
    </array>

    <!-- Network entitlement for translation fallback -->
    <key>com.apple.developer.networking.networkextension</key>
    <array>
        <string>packet-tunnel-provider</string>
    </array>
</dict>
</plist>
```

---

## Deployment Target

### Minimum Requirements

| Setting | Value | Reason |
|---------|-------|--------|
| **iOS Deployment Target** | 15.0+ | SwiftUI requirements |
| **Xcode Version** | 14.0+ | Swift 5.7+ support |
| **Architecture** | arm64 | Native Apple Silicon |

---

## Build Schemes

### Debug Scheme

**Purpose**: Development and testing

**Configuration**:
- `HAVE_LIBOQS`: NOT defined (stub crypto mode)
- Optimization: `-Onone`
- Debug symbols: Enabled
- Assertions: Enabled

**SWORDCOMM Behavior**:
- ✅ All UI features work
- ✅ Integration testing works
- ⚠️ Stub cryptography (NOT SECURE)
- ⚠️ Translation requires manual model addition

### Release Scheme

**Purpose**: Production builds

**Configuration**:
- `HAVE_LIBOQS`: Defined (production crypto)
- Optimization: `-O`
- Debug symbols: Stripped
- Assertions: Disabled (where safe)

**SWORDCOMM Behavior**:
- ✅ Production cryptography (if liboqs integrated)
- ✅ CoreML translation (if model bundled)
- ✅ Full security features
- ✅ Performance optimized

---

## Conditional Compilation

### Swift Preprocessor Flags

```swift
#if DEBUG
    // Development mode
    let emmaDebugMode = true
#else
    // Production mode
    let emmaDebugMode = false
#endif

#if targetEnvironment(simulator)
    // iOS Simulator
    // Performance counters may not work correctly
#else
    // Real device
#endif
```

### Objective-C++ Preprocessor

```objc
#ifdef HAVE_LIBOQS
    // Production crypto with liboqs
    #import <oqs/oqs.h>
#else
    // Stub mode
    #warning "Building without liboqs - using stub cryptography (NOT SECURE)"
#endif
```

---

## Build Verification

### Post-Build Checks

After building, verify:

```bash
# 1. Check that SWORDCOMM frameworks are included
ls -la "$(xcodebuild -showBuildSettings | grep BUILT_PRODUCTS_DIR | awk '{print $3}')"/*.framework

# 2. Verify crypto mode
grep -r "HAVE_LIBOQS" build/

# 3. Check Swift compilation
xcrun swiftc --version
```

### Runtime Checks

When app launches, check console logs:

```
[SWORDCOMM] Initializing SWORDCOMM Security & Translation
[SWORDCOMM] SWORDCOMM initialized successfully
[SWORDCOMM] Running in PRODUCTION CRYPTO mode    <-- Or STUB mode
```

---

## Troubleshooting

### Issue: "Module 'SWORDCOMMSecurityKit' not found"

**Cause**: CocoaPods not installed or workspace not opened

**Fix**:
```bash
pod install
open Signal.xcworkspace  # Not .xcodeproj
```

### Issue: "Undefined symbol: _liboqs_ml_kem_1024_keypair"

**Cause**: liboqs not linked or `HAVE_LIBOQS` not defined

**Fix**:
1. Verify liboqs.xcframework is in project
2. Check `HAVE_LIBOQS=1` in build settings
3. Clean build folder and rebuild

### Issue: Build fails with C++ errors

**Cause**: C++ standard not set correctly

**Fix**: Set **C++ Language Dialect** to `GNU++17` in build settings

### Issue: SwiftUI views not compiling

**Cause**: iOS deployment target too low

**Fix**: Set **iOS Deployment Target** to `15.0` or higher

---

## Performance Optimization

### Build Time Optimization

**Parallel Compilation**:
- Enable in Xcode: Build Settings → Build Options → "Enable Parallel Building"
- Speeds up C++ compilation significantly

**Incremental Builds**:
- SWORDCOMM uses modular architecture for faster incremental builds
- Only modified components rebuild

### Runtime Optimization

**Whole Module Optimization** (Release only):
```
-whole-module-optimization
```

**Link-Time Optimization**:
```
-lto=thin
```

---

## CI/CD Configuration

### GitHub Actions Example

```yaml
name: Build SWORDCOMM Signal-iOS

on: [push, pull_request]

jobs:
  build:
    runs-on: macos-latest

    steps:
    - uses: actions/checkout@v3

    - name: Install CocoaPods
      run: pod install

    - name: Build Signal with SWORDCOMM
      run: |
        xcodebuild \
          -workspace Signal.xcworkspace \
          -scheme Signal \
          -destination 'platform=iOS Simulator,name=iPhone 15' \
          build

    - name: Run Tests
      run: |
        xcodebuild \
          -workspace Signal.xcworkspace \
          -scheme Signal \
          -destination 'platform=iOS Simulator,name=iPhone 15' \
          test
```

---

## Production Deployment Checklist

Before deploying to production:

- [ ] `pod install` executed
- [ ] liboqs XCFramework integrated (if using production crypto)
- [ ] CoreML model bundled (if using translation)
- [ ] `HAVE_LIBOQS=1` defined (for production crypto)
- [ ] Build succeeds in Release configuration
- [ ] All 89+ tests pass (74 SWORDCOMM + 15+ Signal integration)
- [ ] Console shows "PRODUCTION CRYPTO mode"
- [ ] App size acceptable (~100-150 MB increase with crypto + model)
- [ ] Performance benchmarks meet requirements
- [ ] Security audit completed

---

## References

- **CocoaPods**: https://cocoapods.org/
- **CMake**: https://cmake.org/documentation/
- **Xcode Build Settings**: https://developer.apple.com/documentation/xcode/build-settings-reference
- **Swift Package Manager**: https://swift.org/package-manager/

---

**Document Version**: 1.0.0
**Last Updated**: 2025-11-06
**Phase**: 4 - Signal Integration
