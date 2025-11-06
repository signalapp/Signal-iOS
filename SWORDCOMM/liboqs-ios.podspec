Pod::Spec.new do |s|
  s.name             = 'liboqs-ios'
  s.version          = '0.11.0'
  s.summary          = 'Open Quantum Safe library for iOS'
  s.description      = <<-DESC
    liboqs is an open source C library for quantum-safe cryptographic algorithms.
    This podspec wraps liboqs for iOS integration with SWORDCOMM SecurityKit.
  DESC

  s.homepage         = 'https://github.com/open-quantum-safe/liboqs'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Open Quantum Safe' => 'https://openquantumsafe.org' }
  s.source           = {
    :git => 'https://github.com/open-quantum-safe/liboqs.git',
    :tag => '0.11.0'
  }

  s.ios.deployment_target = '15.0'

  # We'll use prebuilt xcframework approach for simplicity
  # In production, this should be built from source

  # For now, create a vendored framework structure
  s.vendored_frameworks = 'liboqs.xcframework'

  s.preserve_paths = 'liboqs.xcframework'

  # Build settings
  s.pod_target_xcconfig = {
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES' => 'YES'
  }

  s.prepare_command = <<-CMD
    # Note: This is a placeholder
    # In production, you should:
    # 1. Download pre-built xcframework from GitHub releases
    # 2. Or build from source using CMake with iOS toolchain
    #
    # For now, we'll use the stub Kyber implementation
    echo "liboqs preparation step - TODO: Add actual liboqs build"
  CMD
end
