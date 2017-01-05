Pod::Spec.new do |s|
  s.name         = "GRKOpenSSLFramework"
  s.version      = "1.0.1.#{("a".."z").to_a.index 't'}"
  s.summary      = "OpenSSL for iOS and OS X"
  s.description  = "OpenSSL Framework binaries."
  s.homepage     = "https://github.com/levigroker/OpenSSL/"
  s.license	     = { :type => 'OpenSSL (OpenSSL/SSLeay)', :file => 'LICENSE.txt' }
  s.source       = { :git => "https://github.com/levigroker/OpenSSL.git", :tag => "#{s.version}" }
  s.authors       =  {'Levi Brown' => 'levigroker@gmail.com'}
  
  s.ios.deployment_target = '9.0'
  s.ios.vendored_frameworks = 'OpenSSL-iOS/bin/openssl.framework'

  s.osx.deployment_target = '10.10'
  s.osx.vendored_frameworks = 'OpenSSL-macOS/bin/openssl.framework'
end
