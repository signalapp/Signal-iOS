Pod::Spec.new do |s|
  s.name         = "YapDatabase"
  s.version      = "2.3"
  s.summary      = "A key/value store built atop sqlite for iOS & Mac."
  s.homepage     = "https://github.com/yaptv/YapDatabase"
  s.license      = 'MIT'
  s.ios.deployment_target = '6.1'
  s.osx.deployment_target = '10.8'
  s.library      = 'sqlite3'
  s.author       = { "Robbie Hanson" => "robbiehanson@deusty.com" }
  s.source       = { :git => "https://github.com/yaptv/YapDatabase.git", :tag => s.version.to_s }

  s.source_files = 'YapDatabase/**/*.{h,m,mm}'
  s.xcconfig     = { 'OTHER_LDFLAGS' => '-weak_library /usr/lib/libc++.dylib' }

  s.private_header_files = 'YapDatabase/**/Internal/*.h'
  s.dependency 'CocoaLumberjack', '~> 1.6.3'

  s.requires_arc = true

end
