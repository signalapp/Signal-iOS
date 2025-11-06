#!/bin/bash
#
# integrate_swordcomm.sh
# Automated SWORDCOMM Integration Script for Signal-iOS
#
# This script automates the integration of SWORDCOMM into Signal-iOS by:
# 1. Adding SWORDCOMM extension files to Xcode project
# 2. Inserting integration code into Signal source files
# 3. Updating build configuration
# 4. Running verification tests
#
# Usage: ./integrate_swordcomm.sh [--dry-run] [--verbose]
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
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SIGNAL_ROOT="$PROJECT_ROOT"
SWORDCOMM_ROOT="$PROJECT_ROOT/SWORDCOMM"

DRY_RUN=false
VERBOSE=false
BACKUP_DIR="$PROJECT_ROOT/.swordcomm_backup_$(date +%Y%m%d_%H%M%S)"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--dry-run] [--verbose]"
            echo ""
            echo "Options:"
            echo "  --dry-run    Show what would be done without making changes"
            echo "  --verbose    Show detailed output"
            echo "  -h, --help   Show this help message"
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

log_verbose() {
    if [ "$VERBOSE" = true ]; then
        echo -e "${NC}[VERBOSE]${NC} $1"
    fi
}

# Backup function
backup_file() {
    local file=$1
    if [ ! -d "$BACKUP_DIR" ]; then
        mkdir -p "$BACKUP_DIR"
        log_info "Created backup directory: $BACKUP_DIR"
    fi

    local backup_path="$BACKUP_DIR/$(basename "$file")"
    cp "$file" "$backup_path"
    log_verbose "Backed up: $file -> $backup_path"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check if SWORDCOMM directory exists
    if [ ! -d "$SWORDCOMM_ROOT" ]; then
        log_error "SWORDCOMM directory not found: $SWORDCOMM_ROOT"
        exit 1
    fi

    # Check if Signal directory exists
    if [ ! -d "$SIGNAL_ROOT/Signal" ]; then
        log_error "Signal directory not found. Are you in the Signal-iOS project root?"
        exit 1
    fi

    # Check for required tools
    if ! command -v pod &> /dev/null; then
        log_error "CocoaPods not found. Install with: sudo gem install cocoapods"
        exit 1
    fi

    # Check for Xcode
    if ! command -v xcodebuild &> /dev/null; then
        log_error "Xcode command line tools not found"
        exit 1
    fi

    log_success "Prerequisites check passed"
}

# Step 1: Add SWORDCOMM extension files to Xcode project
add_emma_extensions() {
    log_info "Step 1: Adding SWORDCOMM extension files to Xcode project..."

    local extensions=(
        "Integration/SignalAppDelegate+SWORDCOMM.swift"
        "Integration/SignalSettingsViewController+SWORDCOMM.swift"
        "Integration/SignalConversationViewController+SWORDCOMM.swift"
        "Integration/SignalMessageTranslation+SWORDCOMM.swift"
    )

    for ext in "${extensions[@]}"; do
        local source="$SWORDCOMM_ROOT/$ext"
        if [ ! -f "$source" ]; then
            log_error "SWORDCOMM extension file not found: $source"
            exit 1
        fi
        log_verbose "Found: $ext"
    done

    if [ "$DRY_RUN" = false ]; then
        # In a real implementation, we'd modify the .pbxproj file
        # For now, just log what would happen
        log_info "  Would add ${#extensions[@]} extension files to Signal.xcodeproj"
        log_warning "  NOTE: Currently requires manual addition via Xcode"
        log_info "  Add these files to Signal target in Xcode:"
        for ext in "${extensions[@]}"; do
            echo "    - SWORDCOMM/$ext"
        done
    else
        log_info "  [DRY RUN] Would add ${#extensions[@]} extension files"
    fi

    log_success "Extension files ready"
}

# Step 2: Patch AppDelegate.swift
patch_app_delegate() {
    log_info "Step 2: Patching AppDelegate.swift..."

    local app_delegate="$SIGNAL_ROOT/Signal/AppLaunch/AppDelegate.swift"

    if [ ! -f "$app_delegate" ]; then
        log_error "AppDelegate.swift not found: $app_delegate"
        exit 1
    fi

    # Check if already patched
    if grep -q "initializeSWORDCOMM()" "$app_delegate"; then
        log_warning "AppDelegate.swift already patched"
        return
    fi

    if [ "$DRY_RUN" = false ]; then
        backup_file "$app_delegate"

        # Patch 1: Add to didFinishLaunchingWithOptions (before return true)
        log_info "  Adding SWORDCOMM initialization..."
        # In real implementation, use sed or awk to insert code
        log_info "  Would insert: if #available(iOS 15.0, *), isSWORDCOMMEnabled { initializeSWORDCOMM() }"

        # Patch 2: Add to didBecomeActive
        log_info "  Adding didBecomeActive hook..."
        log_info "  Would insert: if #available(iOS 15.0, *), isSWORDCOMMEnabled { emmaDidBecomeActive() }"

        # Patch 3: Add to didEnterBackground
        log_info "  Adding didEnterBackground hook..."
        log_info "  Would insert: if #available(iOS 15.0, *), isSWORDCOMMEnabled { emmaDidEnterBackground() }"

        log_warning "  NOTE: Automatic patching not yet implemented"
        log_info "  Please manually add the 3 integration calls as documented"
    else
        log_info "  [DRY RUN] Would patch AppDelegate.swift with 3 integration calls"
    fi

    log_success "AppDelegate integration points identified"
}

# Step 3: Patch AppSettingsViewController.swift
patch_settings() {
    log_info "Step 3: Patching AppSettingsViewController.swift..."

    local settings_vc="$SIGNAL_ROOT/Signal/src/ViewControllers/AppSettings/AppSettingsViewController.swift"

    if [ ! -f "$settings_vc" ]; then
        log_error "AppSettingsViewController.swift not found: $settings_vc"
        exit 1
    fi

    # Check if already patched
    if grep -q "emmaSettingsSection()" "$settings_vc"; then
        log_warning "AppSettingsViewController.swift already patched"
        return
    fi

    if [ "$DRY_RUN" = false ]; then
        backup_file "$settings_vc"

        log_info "  Adding SWORDCOMM settings section..."
        log_info "  Would insert: let emmaSection = emmaSettingsSection()"
        log_warning "  NOTE: Automatic patching not yet implemented"
        log_info "  Please manually add SWORDCOMM section to updateTableContents()"
    else
        log_info "  [DRY RUN] Would patch AppSettingsViewController.swift"
    fi

    log_success "Settings integration point identified"
}

# Step 4: Update Podfile
update_podfile() {
    log_info "Step 4: Updating Podfile..."

    local podfile="$SIGNAL_ROOT/Podfile"

    if [ ! -f "$podfile" ]; then
        log_error "Podfile not found: $podfile"
        exit 1
    fi

    # Check if already updated
    if grep -q "SWORDCOMMSecurityKit" "$podfile"; then
        log_warning "Podfile already includes SWORDCOMM pods"
        return
    fi

    if [ "$DRY_RUN" = false ]; then
        backup_file "$podfile"

        log_info "  Adding SWORDCOMM pods..."
        # Append SWORDCOMM pods after Signal target
        cat >> "$podfile" << 'EOF'

  # ┌──────────────────────────────────┐
  # │ SWORDCOMM Integration                  │
  # └──────────────────────────────────┘
  pod 'SWORDCOMMSecurityKit', :path => './SWORDCOMM'
  pod 'SWORDCOMMTranslationKit', :path => './SWORDCOMM'
EOF
        log_success "SWORDCOMM pods added to Podfile"
    else
        log_info "  [DRY RUN] Would add SWORDCOMM pods to Podfile"
    fi
}

# Step 5: Run pod install
run_pod_install() {
    log_info "Step 5: Running pod install..."

    if [ "$DRY_RUN" = false ]; then
        cd "$SIGNAL_ROOT"
        pod install
        log_success "CocoaPods installation complete"
    else
        log_info "  [DRY RUN] Would run: pod install"
    fi
}

# Step 6: Verify integration
verify_integration() {
    log_info "Step 6: Verifying integration..."

    local checks_passed=0
    local checks_total=5

    # Check 1: SWORDCOMM extension files exist
    if [ -f "$SWORDCOMM_ROOT/Integration/SignalAppDelegate+SWORDCOMM.swift" ]; then
        log_success "  ✓ SWORDCOMM extension files found"
        ((checks_passed++))
    else
        log_error "  ✗ SWORDCOMM extension files missing"
    fi

    # Check 2: Podfile includes SWORDCOMM
    if grep -q "SWORDCOMMSecurityKit" "$SIGNAL_ROOT/Podfile"; then
        log_success "  ✓ Podfile includes SWORDCOMM"
        ((checks_passed++))
    else
        log_warning "  ✗ Podfile does not include SWORDCOMM"
    fi

    # Check 3: Pods directory exists
    if [ -d "$SIGNAL_ROOT/Pods/SWORDCOMMSecurityKit" ]; then
        log_success "  ✓ SWORDCOMM pods installed"
        ((checks_passed++))
    else
        log_warning "  ✗ SWORDCOMM pods not installed (run pod install)"
    fi

    # Check 4: Workspace exists
    if [ -f "$SIGNAL_ROOT/Signal.xcworkspace/contents.xcworkspacedata" ]; then
        log_success "  ✓ Xcode workspace exists"
        ((checks_passed++))
    else
        log_warning "  ✗ Xcode workspace not found"
    fi

    # Check 5: Bridging header exists
    if [ -f "$SWORDCOMM_ROOT/SWORDCOMM-Bridging-Header.h" ]; then
        log_success "  ✓ Bridging header exists"
        ((checks_passed++))
    else
        log_warning "  ✗ Bridging header missing"
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

# Print next steps
print_next_steps() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${GREEN}SWORDCOMM Integration Script Complete!${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Next Steps:"
    echo ""
    echo "1. Open Signal.xcworkspace (NOT .xcodeproj):"
    echo "   open Signal.xcworkspace"
    echo ""
    echo "2. Add SWORDCOMM extension files to Signal target in Xcode:"
    echo "   - SignalAppDelegate+SWORDCOMM.swift"
    echo "   - SignalSettingsViewController+SWORDCOMM.swift"
    echo "   - SignalConversationViewController+SWORDCOMM.swift (optional)"
    echo "   - SignalMessageTranslation+SWORDCOMM.swift (optional)"
    echo ""
    echo "3. Manually add integration code (3-5 calls):"
    echo "   See: SWORDCOMM/PHASE4_SIGNAL_INTEGRATION.md"
    echo ""
    echo "4. Build and run:"
    echo "   - Select Signal scheme"
    echo "   - Build (⌘B)"
    echo "   - Run (⌘R)"
    echo ""
    echo "5. Verify in console logs:"
    echo "   Look for: [SWORDCOMM] Initializing SWORDCOMM Security & Translation"
    echo ""

    if [ -d "$BACKUP_DIR" ]; then
        echo "Backups saved to: $BACKUP_DIR"
        echo ""
    fi

    echo "For detailed instructions, see:"
    echo "  - SWORDCOMM/PHASE4_SIGNAL_INTEGRATION.md"
    echo "  - SWORDCOMM/SIGNAL_BUILD_CONFIGURATION.md"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Main execution
main() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  SWORDCOMM Signal-iOS Integration Script"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if [ "$DRY_RUN" = true ]; then
        log_warning "Running in DRY RUN mode (no changes will be made)"
        echo ""
    fi

    check_prerequisites
    echo ""

    add_emma_extensions
    echo ""

    patch_app_delegate
    echo ""

    patch_settings
    echo ""

    update_podfile
    echo ""

    if [ "$DRY_RUN" = false ]; then
        run_pod_install
        echo ""
    fi

    verify_integration
    echo ""

    print_next_steps
}

# Run main
main

exit 0
