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

  s.platform     = :ios, '9.0'
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

  s.resources = ["SignalServiceKit/Resources/Certificates/*"]

  s.dependency 'Curve25519Kit'
  s.dependency 'CocoaLumberjack'
  s.dependency 'AFNetworking'
  s.dependency 'AxolotlKit'
  s.dependency 'Mantle'
  s.dependency 'YapDatabase/SQLCipher'
  s.dependency 'SocketRocket'
  s.dependency 'libPhoneNumber-iOS'
  s.dependency 'GRKOpenSSLFramework'
  s.dependency 'SAMKeychain'
  s.dependency 'Reachability'
  s.dependency 'SwiftProtobuf'

  # Avoid PromiseKit 5/6 for now.
  # From the maintainer:
  # > PromiseKit 5 has been released, but is not yet fully documented, 
  # > so we advise sticking with version 4 for the time being.
  s.dependency 'PromiseKit', "~> 4.0"

  s.test_spec 'Tests' do |test_spec|
    test_spec.source_files = 'SignalServiceKit/tests/**/*.{h,m,swift}'
  end
end
