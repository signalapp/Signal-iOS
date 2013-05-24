Pod::Spec.new do |s|
  s.name         = "OpenSSL"
  s.version      = "1.0.1e"
  s.summary      = "OpenSSL for iOS with download and build script."
  s.description  = "Builds OpenSSL for armv7, armv7s and the iOS simulator."
  s.homepage     = "https://github.com/justinplouffe/OpenSSL"
  s.license	     = 'OpenSSL (OpenSSL/SSLeay)'

  s.author       = 'Justin Plouffe'
  s.source       = { :git => "https://github.com/justinplouffe/OpenSSL.git", :tag => "1.0.1e" }

  s.platform     = :ios, '6.0'
  s.source_files = 'include/openssl/**/*.h'
  s.public_header_files = 'include/openssl/**/.h'
  s.preserve_paths = 'lib/libcrypto.a', 'lib/libssl.a'
  s.library	  = 'crypto', 'ssl'
  s.xcconfig	 = { 'LIBRARY_SEARCH_PATHS' => '"$(SRCROOT)/Pods/OpenSSL"' }
  
  s.pre_install do |pod, target_definition|
    Dir.chdir(pod.root){ `sh ./build.sh` }
  end
end
