#
# Be sure to run `pod lib lint TextSecureKit.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = "TextSecureKit"
  s.version          = "0.0.4"
  s.summary          = "An Objective-C library for communicating via TextSecure."

  s.description      = <<-DESC
  TextSecureKit is a library for the TextSecure protocol for iOS & OS X
                       DESC

  s.homepage         = "https://github.com/WhisperSystems/TextSecureKit"
  s.license          = 'GPLv3'
  s.author           = { "Frederic Jacobs" => "github@fredericjacobs.com" }
  s.source           = { :git => "https://github.com/WhisperSystems/TextSecureKit.git", :tag => s.version.to_s }
  s.social_media_url = 'https://twitter.com/FredericJacobs'

  s.platform     = :ios, '8.0'
  #s.ios.deployment_target = '8.0'
  #s.osx.deployment_target = '10.9'
  s.requires_arc = true
  s.source_files = 'src/**/*.{h,m,mm}'

  s.resource = 'src/Security/PinningCertificate/textsecure.cer'
  s.prefix_header_file = 'src/TSPrefix.h'
  s.xcconfig = { 'OTHER_CFLAGS' => '$(inherited) -DSQLITE_HAS_CODEC' }

  s.dependency '25519'
  s.dependency 'CocoaLumberjack'
  s.dependency 'AFNetworking'
  s.dependency 'AxolotlKit'
  s.dependency 'Mantle'
  s.dependency 'YapDatabase/SQLCipher'
  s.dependency 'SocketRocket-PinningPolicy'
  s.dependency 'libPhoneNumber-iOS'
  s.dependency 'SSKeychain'
  s.dependency 'TwistedOakCollapsingFutures'
end
