Pod::Spec.new do |s|
  s.name         = "OpenSSL"
  s.version      = "1.0.1e"
  s.summary      = "Pre-built OpenSSL for iOS and OSX"
  s.description  = "Supports OSX and iPhone Simulator,armv7,armv7s,arm64,x86_64"
  s.homepage     = "https://github.com/krzak/OpenSSL"
  s.license	     = 'OpenSSL (OpenSSL/SSLeay)'

  s.author       = 'Marcin Krzyżanowski'
  s.source       = { :git => "https://github.com/krzak/OpenSSL.git", :tag => "#{s.version}" }
  
  s.ios.platform     = :ios, '6.0'
  s.ios.source_files        = 'include-ios/openssl/**/*.h'
  s.ios.public_header_files = 'include-ios/openssl/**/.h'
  s.ios.preserve_paths = 'lib-ios/libcrypto.a', 'lib-ios/libssl.a'
  s.ios.vendored_libraries = 'lib-ios/libcrypto.a', 'lib-ios/libssl.a'

  s.osx.platform     = :osx, '10.8'
  s.osx.source_files        = 'include-osx/openssl/**/*.h'
  s.osx.public_header_files = 'include-osx/openssl/**/.h'
  s.osx.preserve_paths = 'lib-osx/libcrypto.a', 'lib-osx/libssl.a'
  s.osx.vendored_libraries = 'lib-osx/libcrypto.a', 'lib-osx/libssl.a'

  s.libraries = 'ssl', 'crypto'
  s.xcconfig	 = { 'LIBRARY_SEARCH_PATHS' => '"$(SRCROOT)/Pods/OpenSSL"' }
end
