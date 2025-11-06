# liboqs Integration Guide for SWORDCOMM iOS

**Phase**: 3C - Production Cryptography
**Library**: liboqs (Open Quantum Safe)
**Version**: 0.10.1+
**Algorithms**: ML-KEM-1024 (FIPS 203), ML-DSA-87 (FIPS 204)

---

## Overview

SWORDCOMM iOS uses **liboqs** for production-grade post-quantum cryptography. This document explains how to integrate liboqs into the iOS build.

### Integration Options

There are **three ways** to integrate liboqs:

1. **Stub Mode** (current): Uses random data - NOT SECURE, for development only
2. **Pre-compiled XCFramework** (recommended): Fast, easy, production-ready
3. **Build from Source**: Full control, requires build toolchain

---

## Option 1: Stub Mode (Development Only)

**Current status**: SWORDCOMM is in stub mode by default.

### Characteristics
- ✅ Works immediately, no setup required
- ✅ Allows UI and integration testing
- ❌ **NOT SECURE** - uses random data instead of real crypto
- ❌ Cannot communicate with SWORDCOMM-Android
- ❌ Signatures always verify (false positives)

### Detection
When SWORDCOMM runs in stub mode, you'll see log messages:
```
[SWORDCOMM] liboqs NOT COMPILED - using stub implementations
[SWORDCOMM] Generated ML-KEM-1024 keypair - STUB MODE (NOT SECURE)
[SWORDCOMM] Generated ML-DSA-87 keypair - STUB MODE (NOT SECURE)
```

### To Continue in Stub Mode
No action needed. SWORDCOMM will continue to work for development and testing, but **do not use in production**.

---

## Option 2: Pre-compiled XCFramework (Recommended)

### Step 1: Download or Build liboqs XCFramework

#### Option A: Download Pre-built
If available, download a pre-built liboqs XCFramework with ML-KEM and ML-DSA support.

#### Option B: Build XCFramework

**Requirements**:
- Xcode 14+
- CMake 3.20+
- macOS 13+ (for building)

**Build Script**:

```bash
#!/bin/bash
# build_liboqs_xcframework.sh

set -e

LIBOQS_VERSION="0.10.1"
LIBOQS_URL="https://github.com/open-quantum-safe/liboqs/archive/refs/tags/${LIBOQS_VERSION}.tar.gz"

# Create build directory
mkdir -p liboqs-build
cd liboqs-build

# Download liboqs
if [ ! -d "liboqs-${LIBOQS_VERSION}" ]; then
    curl -L "${LIBOQS_URL}" -o liboqs.tar.gz
    tar xzf liboqs.tar.gz
fi

cd "liboqs-${LIBOQS_VERSION}"

# Build for iOS (arm64) - Device
mkdir -p build-ios
cd build-ios
cmake .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
    -DCMAKE_INSTALL_PREFIX=../install-ios \
    -DOQS_USE_OPENSSL=OFF \
    -DOQS_BUILD_ONLY_LIB=ON \
    -DOQS_MINIMAL_BUILD="KEM_ml_kem_1024;SIG_ml_dsa_87"
make -j$(sysctl -n hw.ncpu)
make install
cd ..

# Build for iOS Simulator (arm64 + x86_64)
mkdir -p build-ios-sim
cd build-ios-sim
cmake .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
    -DCMAKE_OSX_SYSROOT=iphonesimulator \
    -DCMAKE_INSTALL_PREFIX=../install-ios-sim \
    -DOQS_USE_OPENSSL=OFF \
    -DOQS_BUILD_ONLY_LIB=ON \
    -DOQS_MINIMAL_BUILD="KEM_ml_kem_1024;SIG_ml_dsa_87"
make -j$(sysctl -n hw.ncpu)
make install
cd ..

# Create XCFramework
xcodebuild -create-xcframework \
    -library install-ios/lib/liboqs.a \
    -headers install-ios/include \
    -library install-ios-sim/lib/liboqs.a \
    -headers install-ios-sim/include \
    -output liboqs.xcframework

echo "✅ liboqs.xcframework created successfully!"
echo "   Copy it to SWORDCOMM/Frameworks/"
```

**Run the build**:
```bash
chmod +x build_liboqs_xcframework.sh
./build_liboqs_xcframework.sh
```

**Build time**: ~5-10 minutes

### Step 2: Add XCFramework to Project

```bash
# Copy to SWORDCOMM frameworks directory
mkdir -p SWORDCOMM/Frameworks
cp -R liboqs-build/liboqs-0.10.1/liboqs.xcframework SWORDCOMM/Frameworks/
```

### Step 3: Update Podfile

Edit `SWORDCOMM/SWORDCOMMSecurityKit.podspec`:

```ruby
Pod::Spec.new do |s|
  s.name         = 'SWORDCOMMSecurityKit'
  s.version      = '1.2.0'
  # ... existing config ...

  # Add liboqs XCFramework
  s.vendored_frameworks = 'Frameworks/liboqs.xcframework'

  # Enable liboqs in build
  s.pod_target_xcconfig = {
    'GCC_PREPROCESSOR_DEFINITIONS' => 'HAVE_LIBOQS=1',
    'OTHER_CPLUSPLUSFLAGS' => '-DHAVE_LIBOQS=1'
  }
end
```

### Step 4: Update CMakeLists.txt

Edit `SWORDCOMM/CMakeLists.txt`:

```cmake
# Add liboqs if available
find_library(LIBOQS_LIBRARY NAMES oqs PATHS ${CMAKE_CURRENT_SOURCE_DIR}/Frameworks/liboqs.xcframework)

if(LIBOQS_LIBRARY)
    message(STATUS "liboqs found: ${LIBOQS_LIBRARY}")
    add_definitions(-DHAVE_LIBOQS=1)
    target_link_libraries(SWORDCOMMSecurityKit PRIVATE ${LIBOQS_LIBRARY})
else()
    message(WARNING "liboqs NOT found - using stub mode")
endif()
```

### Step 5: Rebuild and Test

```bash
pod install
xcodebuild -workspace Swordcomm-IOS.xcworkspace -scheme Signal clean build
```

**Expected log output**:
```
[SWORDCOMM] liboqs initialization - version: 0.10.1
[SWORDCOMM] liboqs initialized successfully - ML-KEM-1024 and ML-DSA-87 enabled
[SWORDCOMM] Generated ML-KEM-1024 keypair (NIST FIPS 203) - PRODUCTION
[SWORDCOMM] Generated ML-DSA-87 keypair (NIST FIPS 204) - PRODUCTION
```

✅ **Production crypto is now enabled!**

---

## Option 3: Build from Source (Advanced)

For developers who want to compile liboqs directly into the app:

### Step 1: Add liboqs as Git Submodule

```bash
cd SWORDCOMM/ThirdParty
git submodule add https://github.com/open-quantum-safe/liboqs.git
cd liboqs
git checkout 0.10.1
```

### Step 2: Create Build Script

Create `SWORDCOMM/ThirdParty/build_liboqs.sh`:

```bash
#!/bin/bash
set -e

cd "$(dirname "$0")/liboqs"

# Configure for iOS
cmake -B build-ios -S . \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
    -DOQS_USE_OPENSSL=OFF \
    -DOQS_BUILD_ONLY_LIB=ON \
    -DOQS_MINIMAL_BUILD="KEM_ml_kem_1024;SIG_ml_dsa_87"

# Build
cmake --build build-ios --parallel

echo "✅ liboqs built successfully"
```

### Step 3: Update Xcode Build Phases

Add **Run Script** phase in SWORDCOMM SecurityKit target:

```bash
# Build liboqs if not already built
if [ ! -f "${PROJECT_DIR}/SWORDCOMM/ThirdParty/liboqs/build-ios/lib/liboqs.a" ]; then
    echo "Building liboqs..."
    bash "${PROJECT_DIR}/SWORDCOMM/ThirdParty/build_liboqs.sh"
fi
```

### Step 4: Link liboqs

In Xcode **Build Settings**:

**Header Search Paths**:
```
$(PROJECT_DIR)/SWORDCOMM/ThirdParty/liboqs/build-ios/include
```

**Library Search Paths**:
```
$(PROJECT_DIR)/SWORDCOMM/ThirdParty/liboqs/build-ios/lib
```

**Other Linker Flags**:
```
-loqs
```

**Preprocessor Macros**:
```
HAVE_LIBOQS=1
```

---

## Verification

### Test liboqs Integration

Run SWORDCOMM unit tests:

```bash
xcodebuild test \
    -workspace Swordcomm-IOS.xcworkspace \
    -scheme SWORDCOMMSecurityKitTests \
    -destination 'platform=iOS Simulator,name=iPhone 15'
```

### Test Cross-Platform Communication

1. **Generate keypair on iOS**:
```swift
let mlkem = EMMLKEM1024.generateKeypair()
print("Public Key: \(mlkem.publicKey.base64EncodedString())")
```

2. **Send public key to SWORDCOMM-Android**
3. **Perform encapsulation on Android**
4. **Verify shared secret matches on decapsulation**

### Performance Benchmarks

Expected performance on iPhone 15 Pro:

| Operation | Time | Notes |
|-----------|------|-------|
| ML-KEM-1024 Keypair | ~0.8ms | One-time per session |
| ML-KEM-1024 Encapsulation | ~0.9ms | Per message |
| ML-KEM-1024 Decapsulation | ~0.9ms | Per message |
| ML-DSA-87 Keypair | ~2.5ms | One-time per identity |
| ML-DSA-87 Sign | ~4.2ms | Per signed message |
| ML-DSA-87 Verify | ~2.1ms | Per signature check |

---

## Troubleshooting

### Issue: "Symbol not found: _OQS_KEM_alg_ml_kem_1024"

**Cause**: liboqs was not built with ML-KEM-1024 enabled

**Fix**: Rebuild with `-DOQS_MINIMAL_BUILD="KEM_ml_kem_1024;SIG_ml_dsa_87"`

### Issue: "liboqs NOT COMPILED - using stub implementations"

**Cause**: `HAVE_LIBOQS` preprocessor macro not set

**Fix**: Add `-DHAVE_LIBOQS=1` to **Preprocessor Macros** in build settings

### Issue: Build fails with "No such file or directory: oqs/oqs.h"

**Cause**: Header search paths not configured

**Fix**: Add `$(PROJECT_DIR)/SWORDCOMM/Frameworks/liboqs.xcframework/Headers` to **Header Search Paths**

### Issue: Shared secret mismatch between iOS and Android

**Cause**: Different liboqs versions or configuration

**Fix**: Ensure both platforms use same liboqs version (0.10.1+) with same algorithms

---

## liboqs Minimal Build Configuration

To minimize binary size, build only required algorithms:

```cmake
-DOQS_MINIMAL_BUILD="KEM_ml_kem_1024;SIG_ml_dsa_87"
```

This reduces liboqs from ~50MB to ~2MB.

### Full Algorithm List (if needed later)

```cmake
-DOQS_MINIMAL_BUILD="KEM_ml_kem_512;KEM_ml_kem_768;KEM_ml_kem_1024;SIG_ml_dsa_44;SIG_ml_dsa_65;SIG_ml_dsa_87"
```

---

## Production Deployment Checklist

Before shipping to production:

- [ ] liboqs XCFramework integrated (not stub mode)
- [ ] Build settings include `HAVE_LIBOQS=1`
- [ ] Unit tests pass with production crypto
- [ ] Cross-platform communication tested with SWORDCOMM-Android
- [ ] Performance benchmarks meet requirements
- [ ] Binary size acceptable (~2-3MB for liboqs)
- [ ] No console warnings about "STUB MODE"
- [ ] Signature verification works correctly (not always true)
- [ ] Key exchange produces matching shared secrets

---

## References

- **liboqs GitHub**: https://github.com/open-quantum-safe/liboqs
- **liboqs Documentation**: https://openquantumsafe.org/liboqs/
- **NIST FIPS 203** (ML-KEM): https://csrc.nist.gov/pubs/fips/203/final
- **NIST FIPS 204** (ML-DSA): https://csrc.nist.gov/pubs/fips/204/final
- **SWORDCOMM Wrapper API**: `SWORDCOMM/SecurityKit/Native/liboqs_wrapper.h`

---

**Document Version**: 1.0.0
**Last Updated**: 2025-11-06
**Phase**: 3C - Production Cryptography
