Pod::Spec.new do |s|
  s.name             = 'EMMATranslationKit'
  s.version          = '1.0.0'
  s.summary          = 'EMMA Translation Framework for iOS'
  s.description      = <<-DESC
    Enterprise Messaging Military-grade Android (EMMA) translation features ported to iOS.
    Provides Danish-English translation with on-device and network support.
  DESC

  s.homepage         = 'https://github.com/SWORDIntel/Swordcomm-IOS'
  s.license          = { :type => 'AGPL-3.0', :file => '../LICENSE' }
  s.author           = { 'SWORD Intel' => 'https://github.com/SWORDIntel' }
  s.source           = { :git => 'https://github.com/SWORDIntel/Swordcomm-IOS.git', :tag => s.version.to_s }

  s.ios.deployment_target = '15.0'
  s.swift_version = '5.9'

  # Dependencies
  s.dependency 'EMMASecurityKit', '~> 1.0.0'

  # Source files
  s.source_files = [
    'TranslationKit/Native/**/*.{h,cpp}',
    'TranslationKit/Bridge/**/*.{h,mm}',
    'TranslationKit/Swift/**/*.swift'
  ]

  s.public_header_files = [
    'TranslationKit/Bridge/EMTranslationKit.h'
  ]

  # Framework settings
  s.frameworks = 'Foundation', 'CoreML'
  s.libraries = 'c++'

  # Compiler flags
  s.pod_target_xcconfig = {
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'GCC_ENABLE_CPP_EXCEPTIONS' => 'YES',
    'GCC_ENABLE_CPP_RTTI' => 'YES',
    'HEADER_SEARCH_PATHS' => '$(PODS_TARGET_SRCROOT)/../Common $(PODS_TARGET_SRCROOT)/TranslationKit/Native',
    'OTHER_CPLUSPLUSFLAGS' => '-Wall -Wextra'
  }

  # Module map
  s.module_map = 'TranslationKit/Framework/module.modulemap'

  # Info.plist
  s.info_plist = {
    'CFBundleIdentifier' => 'im.swordcomm.emma.translation'
  }
end
