Pod::Spec.new do |s|
  s.name         = "OpenSSL"
  s.version      = "1.0.1e"
  s.summary      = "Pre-built OpenSSL for iOS."
  s.description  = "Supports iPhone Simulator, armv7 and armv7s."
  s.homepage     = "https://github.com/justinplouffe/OpenSSL"
  s.license	     = 'OpenSSL (OpenSSL/SSLeay)'

  s.author       = 'Justin Plouffe'
  s.source       = { :git => "https://github.com/justinplouffe/OpenSSL.git", :tag => "1.0.1e" }

  s.platform     = :ios, '5.1'
  s.source_files = 'include/openssl/**/*.h'
  s.public_header_files = 'include/openssl/**/.h'
  s.preserve_paths = 'libcrypto.a', 'libssl.a'
  s.library	  = 'crypto', 'ssl'
  s.xcconfig	 = { 'LIBRARY_SEARCH_PATHS' => '"$(SRCROOT)/Pods/OpenSSL"' }
end
