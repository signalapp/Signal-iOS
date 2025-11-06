#!/bin/bash
#
# build_liboqs.sh
# Automated liboqs XCFramework Builder for iOS
#
# This script automates the build of liboqs for iOS by:
# 1. Downloading liboqs source code
# 2. Building for iOS device (arm64)
# 3. Building for iOS Simulator (arm64 + x86_64)
# 4. Creating XCFramework bundle
# 5. Verifying the build
#
# Usage: ./build_liboqs.sh [--version VERSION] [--clean] [--minimal]
#

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/.liboqs_build"
LIBOQS_VERSION="0.10.1"
LIBOQS_URL="https://github.com/open-quantum-safe/liboqs/archive/refs/tags/${LIBOQS_VERSION}.tar.gz"
OUTPUT_DIR="$PROJECT_ROOT/EMMA/Frameworks"

CLEAN_BUILD=false
MINIMAL_BUILD=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --version)
            LIBOQS_VERSION="$2"
            LIBOQS_URL="https://github.com/open-quantum-safe/liboqs/archive/refs/tags/${LIBOQS_VERSION}.tar.gz"
            shift 2
            ;;
        --clean)
            CLEAN_BUILD=true
            shift
            ;;
        --minimal)
            MINIMAL_BUILD=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--version VERSION] [--clean] [--minimal]"
            echo ""
            echo "Options:"
            echo "  --version VERSION  Specify liboqs version (default: 0.10.1)"
            echo "  --clean            Clean build directory before building"
            echo "  --minimal          Build only ML-KEM-1024 and ML-DSA-87 (smaller binary)"
            echo "  -h, --help         Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check for CMake
    if ! command -v cmake &> /dev/null; then
        log_error "CMake not found. Install with: brew install cmake"
        exit 1
    fi

    # Check for Xcode
    if ! command -v xcodebuild &> /dev/null; then
        log_error "Xcode command line tools not found"
        exit 1
    fi

    # Check for curl
    if ! command -v curl &> /dev/null; then
        log_error "curl not found"
        exit 1
    fi

    # Check CMake version (need 3.22+)
    CMAKE_VERSION=$(cmake --version | head -n1 | awk '{print $3}')
    CMAKE_MAJOR=$(echo $CMAKE_VERSION | cut -d. -f1)
    CMAKE_MINOR=$(echo $CMAKE_VERSION | cut -d. -f2)

    if [ "$CMAKE_MAJOR" -lt 3 ] || ([ "$CMAKE_MAJOR" -eq 3 ] && [ "$CMAKE_MINOR" -lt 22 ]); then
        log_error "CMake 3.22+ required, found $CMAKE_VERSION"
        exit 1
    fi

    log_success "Prerequisites check passed (CMake $CMAKE_VERSION)"
}

# Clean build directory
clean_build_dir() {
    if [ "$CLEAN_BUILD" = true ]; then
        log_info "Cleaning build directory..."
        rm -rf "$BUILD_DIR"
        log_success "Build directory cleaned"
    fi
}

# Download liboqs source
download_liboqs() {
    log_info "Downloading liboqs v${LIBOQS_VERSION}..."

    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"

    if [ -d "liboqs-${LIBOQS_VERSION}" ]; then
        log_warning "Source directory already exists, skipping download"
        return
    fi

    curl -L "$LIBOQS_URL" -o "liboqs-${LIBOQS_VERSION}.tar.gz"

    if [ ! -f "liboqs-${LIBOQS_VERSION}.tar.gz" ]; then
        log_error "Failed to download liboqs"
        exit 1
    fi

    log_info "Extracting source..."
    tar -xzf "liboqs-${LIBOQS_VERSION}.tar.gz"

    log_success "liboqs source downloaded and extracted"
}

# Configure minimal build (only ML-KEM-1024 and ML-DSA-87)
configure_minimal_build() {
    local build_type=$1
    local extra_flags=""

    if [ "$MINIMAL_BUILD" = true ]; then
        log_info "Configuring minimal build (ML-KEM-1024 + ML-DSA-87 only)..."
        extra_flags="
            -DOQS_MINIMAL_BUILD=ON
            -DOQS_ENABLE_KEM_ml_kem_1024=ON
            -DOQS_ENABLE_SIG_ml_dsa_87=ON
        "
    fi

    echo "$extra_flags"
}

# Build for iOS device (arm64)
build_for_device() {
    log_info "Building liboqs for iOS device (arm64)..."

    cd "$BUILD_DIR"
    mkdir -p "build-ios-device"
    cd "build-ios-device"

    local minimal_flags=$(configure_minimal_build "device")

    cmake "../liboqs-${LIBOQS_VERSION}" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
        -DCMAKE_OSX_ARCHITECTURES=arm64 \
        -DCMAKE_INSTALL_PREFIX="$BUILD_DIR/install-ios-device" \
        -DBUILD_SHARED_LIBS=OFF \
        -DOQS_BUILD_ONLY_LIB=ON \
        -DOQS_USE_OPENSSL=OFF \
        $minimal_flags

    cmake --build . --parallel $(sysctl -n hw.ncpu)
    cmake --install .

    log_success "iOS device build complete"
}

# Build for iOS Simulator (arm64 + x86_64)
build_for_simulator() {
    log_info "Building liboqs for iOS Simulator (arm64 + x86_64)..."

    cd "$BUILD_DIR"
    mkdir -p "build-ios-simulator"
    cd "build-ios-simulator"

    local minimal_flags=$(configure_minimal_build "simulator")

    cmake "../liboqs-${LIBOQS_VERSION}" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
        -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
        -DCMAKE_OSX_SYSROOT=iphonesimulator \
        -DCMAKE_INSTALL_PREFIX="$BUILD_DIR/install-ios-simulator" \
        -DBUILD_SHARED_LIBS=OFF \
        -DOQS_BUILD_ONLY_LIB=ON \
        -DOQS_USE_OPENSSL=OFF \
        $minimal_flags

    cmake --build . --parallel $(sysctl -n hw.ncpu)
    cmake --install .

    log_success "iOS Simulator build complete"
}

# Create XCFramework
create_xcframework() {
    log_info "Creating XCFramework..."

    mkdir -p "$OUTPUT_DIR"

    # Remove existing XCFramework if it exists
    if [ -d "$OUTPUT_DIR/liboqs.xcframework" ]; then
        log_warning "Removing existing XCFramework"
        rm -rf "$OUTPUT_DIR/liboqs.xcframework"
    fi

    xcodebuild -create-xcframework \
        -library "$BUILD_DIR/install-ios-device/lib/liboqs.a" \
        -headers "$BUILD_DIR/install-ios-device/include" \
        -library "$BUILD_DIR/install-ios-simulator/lib/liboqs.a" \
        -headers "$BUILD_DIR/install-ios-simulator/include" \
        -output "$OUTPUT_DIR/liboqs.xcframework"

    if [ ! -d "$OUTPUT_DIR/liboqs.xcframework" ]; then
        log_error "Failed to create XCFramework"
        exit 1
    fi

    log_success "XCFramework created at: $OUTPUT_DIR/liboqs.xcframework"
}

# Verify build
verify_build() {
    log_info "Verifying XCFramework..."

    local checks_passed=0
    local checks_total=5

    # Check 1: XCFramework exists
    if [ -d "$OUTPUT_DIR/liboqs.xcframework" ]; then
        log_success "  ✓ XCFramework exists"
        ((checks_passed++))
    else
        log_error "  ✗ XCFramework not found"
    fi

    # Check 2: Info.plist exists
    if [ -f "$OUTPUT_DIR/liboqs.xcframework/Info.plist" ]; then
        log_success "  ✓ Info.plist found"
        ((checks_passed++))
    else
        log_error "  ✗ Info.plist missing"
    fi

    # Check 3: iOS device library exists
    if [ -f "$OUTPUT_DIR/liboqs.xcframework/ios-arm64/liboqs.a" ]; then
        log_success "  ✓ iOS device library found"
        ((checks_passed++))
    else
        log_error "  ✗ iOS device library missing"
    fi

    # Check 4: iOS Simulator library exists
    if [ -f "$OUTPUT_DIR/liboqs.xcframework/ios-arm64_x86_64-simulator/liboqs.a" ]; then
        log_success "  ✓ iOS Simulator library found"
        ((checks_passed++))
    else
        log_error "  ✗ iOS Simulator library missing"
    fi

    # Check 5: Headers exist
    if [ -d "$OUTPUT_DIR/liboqs.xcframework/ios-arm64/Headers" ]; then
        local header_count=$(find "$OUTPUT_DIR/liboqs.xcframework/ios-arm64/Headers" -name "*.h" | wc -l)
        log_success "  ✓ Headers found ($header_count headers)"
        ((checks_passed++))
    else
        log_error "  ✗ Headers missing"
    fi

    echo ""
    log_info "Verification: $checks_passed/$checks_total checks passed"

    if [ $checks_passed -eq $checks_total ]; then
        log_success "All verification checks passed!"
        return 0
    else
        log_warning "Some verification checks failed"
        return 1
    fi
}

# Get framework size
get_framework_size() {
    if [ -d "$OUTPUT_DIR/liboqs.xcframework" ]; then
        local size=$(du -sh "$OUTPUT_DIR/liboqs.xcframework" | awk '{print $1}')
        log_info "XCFramework size: $size"

        if [ "$MINIMAL_BUILD" = true ]; then
            log_info "Minimal build includes only ML-KEM-1024 and ML-DSA-87"
        else
            log_info "Full build includes all liboqs algorithms"
        fi
    fi
}

# Print integration instructions
print_integration_instructions() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${GREEN}liboqs XCFramework Build Complete!${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "XCFramework location:"
    echo "  $OUTPUT_DIR/liboqs.xcframework"
    echo ""
    echo "Next Steps:"
    echo ""
    echo "1. Add liboqs.xcframework to your Xcode project:"
    echo "   - Open Signal.xcworkspace"
    echo "   - Drag liboqs.xcframework into project navigator"
    echo "   - Select Signal target → General → Frameworks, Libraries, and Embedded Content"
    echo "   - Ensure 'Embed & Sign' is selected"
    echo ""
    echo "2. Enable production cryptography:"
    echo "   - Open Signal target → Build Settings"
    echo "   - Search for 'Preprocessor Macros'"
    echo "   - Add: HAVE_LIBOQS=1"
    echo ""
    echo "3. Verify integration:"
    echo "   - Build the project (⌘B)"
    echo "   - Look for: [EMMA] Running in PRODUCTION CRYPTO mode"
    echo ""
    echo "4. Update EMMA wrapper (if needed):"
    echo "   - Verify liboqs_wrapper.cpp includes correct algorithm names"
    echo "   - Check that ML-KEM-1024 and ML-DSA-87 are enabled"
    echo ""
    echo "For detailed instructions, see:"
    echo "  - EMMA/LIBOQS_INTEGRATION.md"
    echo "  - EMMA/SIGNAL_BUILD_CONFIGURATION.md"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Main execution
main() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  liboqs XCFramework Builder for iOS"
    echo "  Version: $LIBOQS_VERSION"
    if [ "$MINIMAL_BUILD" = true ]; then
        echo "  Build Type: Minimal (ML-KEM-1024 + ML-DSA-87 only)"
    else
        echo "  Build Type: Full (all algorithms)"
    fi
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    check_prerequisites
    echo ""

    clean_build_dir
    echo ""

    download_liboqs
    echo ""

    build_for_device
    echo ""

    build_for_simulator
    echo ""

    create_xcframework
    echo ""

    verify_build
    echo ""

    get_framework_size
    echo ""

    print_integration_instructions
}

# Run main
main

exit 0
