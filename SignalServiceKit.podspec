#
# Be sure to run `pod lib lint SignalServiceKit.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = "SignalServiceKit"
  s.version          = "0.9.0"
  s.summary          = "An Objective-C library for communicating with the Signal messaging service."

  s.description      = <<-DESC
An Objective-C library for communicating with the Signal messaging service.
  DESC

  s.homepage         = "https://github.com/signalapp/SignalServiceKit"
  s.license          = 'GPLv3'
  s.author           = { "Frederic Jacobs" => "github@fredericjacobs.com" }
  s.source           = { :git => "https://github.com/signalapp/SignalServiceKit.git", :tag => s.version.to_s }
  s.social_media_url = 'https://twitter.com/FredericJacobs'

  s.platform     = :ios, '11.0'
  s.requires_arc = true
  s.source_files = 'SignalServiceKit/src/**/*.{h,m,mm,swift}'

  # We want to use modules to avoid clobbering CocoaLumberjack macros defined
  # by other OWS modules which *also* import CocoaLumberjack. But because we
  # also use Objective-C++, modules are disabled unless we explicitly enable
  # them
  s.compiler_flags = "-fcxx-modules"

  s.prefix_header_file = 'SignalServiceKit/src/TSPrefix.h'
  s.xcconfig = { 'OTHER_CFLAGS' => '$(inherited) -DSQLITE_HAS_CODEC',
                 'USER_HEADER_SEARCH_PATHS' => '$(inherited) $(SRCROOT)/libwebp/src'   }

  s.resources = [
    "SignalServiceKit/Resources/Certificates/*", 
    "SignalServiceKit/Resources/schema.sql"
  ]

  s.dependency 'Curve25519Kit'
  s.dependency 'CocoaLumberjack'
  s.dependency 'AFNetworking/NSURLSession'
  s.dependency 'AxolotlKit'
  s.dependency 'Mantle'
  s.dependency 'YapDatabase/SQLCipher'
  s.dependency 'Starscream'
  s.dependency 'libPhoneNumber-iOS'
  s.dependency 'GRKOpenSSLFramework'
  s.dependency 'SAMKeychain'
  s.dependency 'Reachability'
  s.dependency 'SwiftProtobuf'
  s.dependency 'SignalCoreKit'
  s.dependency 'SignalMetadataKit'
  s.dependency 'GRDB.swift/SQLCipher'
  s.dependency 'libwebp'
  s.dependency 'PromiseKit', "~> 6.0"
  s.dependency 'YYImage/WebP'
  s.dependency 'blurhash'
  s.dependency 'SignalArgon2'

  s.test_spec 'Tests' do |test_spec|
    test_spec.source_files = 'SignalServiceKit/tests/**/*.{h,m,swift}'
    test_spec.resources = 'SignalServiceKit/tests/**/*.json'
  end
end
