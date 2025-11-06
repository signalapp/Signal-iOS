Pod::Spec.new do |s|
  s.name             = 'SWORDCOMMSecurityKit'
  s.version          = '1.0.0'
  s.summary          = 'SWORDCOMM Security Framework for iOS'
  s.description      = <<-DESC
    Secure Worldwide Operations Enterprise Messaging Military-grade Android Real-time Data Communication (SWORDCOMM) security features ported to iOS.
    Provides threat detection, cache operations, memory protection, and post-quantum cryptography.
  DESC

  s.homepage         = 'https://github.com/SWORDIntel/Swordcomm-IOS'
  s.license          = { :type => 'AGPL-3.0', :file => '../LICENSE' }
  s.author           = { 'SWORD Intel' => 'https://github.com/SWORDIntel' }
  s.source           = { :git => 'https://github.com/SWORDIntel/Swordcomm-IOS.git', :tag => s.version.to_s }

  s.ios.deployment_target = '15.0'
  s.swift_version = '5.9'

  # Source files
  s.source_files = [
    'Common/**/*.{h,cpp}',
    'SecurityKit/Native/**/*.{h,cpp}',
    'SecurityKit/Bridge/**/*.{h,mm}',
    'SecurityKit/Swift/**/*.swift'
  ]

  s.public_header_files = [
    'SecurityKit/Bridge/EMSecurityKit.h',
    'Common/ios_platform.h'
  ]

  # Framework settings
  s.frameworks = 'Foundation', 'Security'
  s.libraries = 'c++'

  # Compiler flags
  s.pod_target_xcconfig = {
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'GCC_ENABLE_CPP_EXCEPTIONS' => 'YES',
    'GCC_ENABLE_CPP_RTTI' => 'YES',
    'HEADER_SEARCH_PATHS' => '$(PODS_TARGET_SRCROOT)/Common $(PODS_TARGET_SRCROOT)/SecurityKit/Native',
    'OTHER_CPLUSPLUSFLAGS' => '-Wall -Wextra'
  }

  # Module map
  s.module_map = 'SecurityKit/Framework/module.modulemap'

  # Info.plist
  s.info_plist = {
    'CFBundleIdentifier' => 'im.swordcomm.swordcomm.security'
  }
end
