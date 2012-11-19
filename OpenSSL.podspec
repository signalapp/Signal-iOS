Pod::Spec.new do |s|
  s.name         = "OpenSSL"
  s.version      = "1.0.1c"
  s.summary      = "Pre-built OpenSSL for iOS."
  s.description  = <<-DESC
	Supports iPhone Simulator, armv7 and armv7s.
                    DESC
  s.homepage     = "https://github.com/yaakov-h/OpenSSL"
  s.license	 = 'OpenSSL (OpenSSL/SSLeay)'

  s.author       = 'Yaakov'
  s.source       = { :git => "https://github.com/yaakov-h/OpenSSL.git", :tag => "1.0.1c" }

  s.platform     = :ios, '6.0'
  s.source_files = 'include/openssl/**/*.h'
  s.public_header_files = 'include/openssl/**/.h'
  s.preserve_paths = 'libcrypto.a', 'libssl.a'
  s.library	 = 'crypto', 'ssl'
end
