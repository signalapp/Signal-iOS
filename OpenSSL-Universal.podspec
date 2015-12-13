Pod::Spec.new do |s|
  s.name         = "OpenSSL-Universal"
  s.version      = "1.0.1.q"
  s.summary      = "OpenSSL for iOS and OS X"
  s.description  = "OpenSSL is an SSL/TLS and Crypto toolkit. Deprecated in Mac OS and gone in iOS, this spec gives your project non-deprecated OpenSSL support. Supports OSX and iOS including Simulator (armv7,armv7s,arm64,i386,x86_64)."
  s.homepage     = "http://krzyzanowskim.github.io/OpenSSL/"
  s.license	     = { :type => 'OpenSSL (OpenSSL/SSLeay)', :file => 'LICENSE.txt' }
  s.source       = { :git => "https://github.com/krzyzanowskim/OpenSSL.git", :tag => "#{s.version}" }

  s.authors       =  {'Mark J. Cox' => 'mark@openssl.org',
                     'Ralf S. Engelschall' => 'rse@openssl.org',
                     'Dr. Stephen Henson' => 'steve@openssl.org',
                     'Ben Laurie' => 'ben@openssl.org',
                     'Lutz Jänicke' => 'jaenicke@openssl.org',
                     'Nils Larsch' => 'nils@openssl.org',
                     'Richard Levitte' => 'nils@openssl.org',
                     'Bodo Möller' => 'bodo@openssl.org',
                     'Ulf Möller' => 'ulf@openssl.org',
                     'Andy Polyakov' => 'appro@openssl.org',
                     'Geoff Thorpe' => 'geoff@openssl.org',
                     'Holger Reif' => 'holger@openssl.org',
                     'Paul C. Sutton' => 'geoff@openssl.org',
                     'Eric A. Young' => 'eay@cryptsoft.com',
                     'Tim Hudson' => 'tjh@cryptsoft.com',
                     'Justin Plouffe' => 'plouffe.justin@gmail.com'}
  
  s.ios.platform          = :ios, '6.0'
  s.ios.deployment_target = '6.0'
  s.ios.source_files        = 'include-ios/openssl/**/*.h'
  s.ios.public_header_files = 'include-ios/openssl/**/*.h'
  s.ios.header_dir          = 'openssl'
  s.ios.preserve_paths      = 'lib-ios/libcrypto.a', 'lib-ios/libssl.a'
  s.ios.vendored_libraries  = 'lib-ios/libcrypto.a', 'lib-ios/libssl.a'

  s.watchos.platform          = :watchos, '2.0'
  s.watchos.deployment_target = '2.0'
  s.watchos.source_files        = 'include-watchos/openssl/**/*.h'
  s.watchos.public_header_files = 'include-watchos/openssl/**/*.h'
  s.watchos.header_dir          = 'openssl'
  s.watchos.preserve_paths      = 'lib-watchos/libcrypto.a', 'lib-watchos/libssl.a'
  s.watchos.vendored_libraries  = 'lib-watchos/libcrypto.a', 'lib-watchos/libssl.a'

  s.tvos.platform          = tvos, '9.1'
  s.tvos.deployment_target = '9.1'
  s.tvos.source_files        = 'include-appletv/openssl/**/*.h'
  s.tvos.public_header_files = 'include-appletv/openssl/**/*.h'
  s.tvos.header_dir          = 'openssl'
  s.tvos.preserve_paths      = 'lib-appletv/libcrypto.a', 'lib-appletv/libssl.a'
  s.tvos.vendored_libraries  = 'lib-appletv/libcrypto.a', 'lib-appletv/libssl.a'

  s.osx.platform          = :osx, '10.9'
  s.osx.deployment_target = '10.8'
  s.osx.source_files        = 'include-osx/openssl/**/*.h'
  s.osx.public_header_files = 'include-osx/openssl/**/*.h'
  s.osx.header_dir          = 'openssl'
  s.osx.preserve_paths      = 'lib-osx/libcrypto.a', 'lib-osx/libssl.a'
  s.osx.vendored_libraries  = 'lib-osx/libcrypto.a', 'lib-osx/libssl.a'

  s.libraries = 'ssl', 'crypto'
end
