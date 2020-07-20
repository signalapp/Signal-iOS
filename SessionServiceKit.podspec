#
# Be sure to run `pod lib lint SignalServiceKit.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = "SessionServiceKit"
  s.version          = "1.0.0"
  s.summary          = "A Swift/Objective-C library for communicating with the Session messaging service."

  s.description      = <<-DESC
A Swift/Objective-C library for communicating with the Session messaging service.
  DESC

  s.homepage         = "https://github.com/loki-project/session-ios"
  s.license          = 'GPLv3'
  s.author           = { "Niels Andriesse" => "niels@loki.network" }
  s.source           = { :git => "https://github.com/loki-project/session-ios.git", :tag => s.version.to_s }
  s.social_media_url = 'https://getsession.org/'

  s.platform     = :ios, '10.0'
  #s.ios.deployment_target = '9.0'
  #s.osx.deployment_target = '10.9'
  s.requires_arc = true
  s.source_files = 'SignalServiceKit/src/**/*.{h,m,mm,swift}'

  # We want to use modules to avoid clobbering CocoaLumberjack macros defined
  # by other OWS modules which *also* import CocoaLumberjack. But because we
  # also use Objective-C++, modules are disabled unless we explicitly enable
  # them
  s.compiler_flags = "-fcxx-modules"

  s.prefix_header_file = 'SignalServiceKit/src/TSPrefix.h'
  s.xcconfig = { 'OTHER_CFLAGS' => '$(inherited) -DSQLITE_HAS_CODEC' }

  s.resources = ["SignalServiceKit/Resources/Certificates/*", "SignalServiceKit/src/Loki/Mnemonic/*.txt"]

  s.dependency 'SessionCurve25519Kit', '~> 2.1.3'
  s.dependency 'CocoaLumberjack'
  s.dependency 'CryptoSwift', '~> 1.3'
  s.dependency 'AFNetworking'
  s.dependency 'SessionAxolotlKit', '~> 1.0.7'
  s.dependency 'Mantle'
  s.dependency 'YapDatabase/SQLCipher'
  s.dependency 'Starscream'
  s.dependency 'libPhoneNumber-iOS'
  s.dependency 'GRKOpenSSLFramework'
  s.dependency 'SAMKeychain'
  s.dependency 'Reachability'
  s.dependency 'SwiftProtobuf', '~> 1.5.0'
  s.dependency 'SessionCoreKit', '~> 1.0.0'
  s.dependency 'SessionMetadataKit', '~> 1.0.7'
  s.dependency 'PromiseKit', '~> 6.0'

  s.test_spec 'Tests' do |test_spec|
    test_spec.source_files = 'SignalServiceKit/tests/**/*.{h,m,swift}'
  end
end
