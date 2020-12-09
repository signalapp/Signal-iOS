#
# Be sure to run `pod lib lint SignalRingRTC.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = "SignalRingRTC"
  s.version          = "2.8.8"
  s.summary          = "A Swift & Objective-C library used by the Signal iOS app for WebRTC interactions."

  s.description      = <<-DESC
    A Swift & Objective-C library used by the Signal iOS app for WebRTC interactions."
  DESC

  s.license          = 'GPLv3'
  s.homepage         = 'https://github.com/signalapp/ringrtc'
  s.source           = { git: 'https://github.com/signalapp/ringrtc.git', tag: "v#{s.version.to_s}" }
  s.author           = { 'iOS Team': 'ios@signal.org' }
  s.social_media_url = 'https://twitter.com/signalapp'

  s.platform     = :ios, '11.0'
  s.requires_arc = true

  s.source_files  = 'RingRTC/src/ios/SignalRingRTC/SignalRingRTC/**/*.{h,m,swift}', 'WebRTC/Build/libringrtc/**/*.h'
  s.public_header_files = 'RingRTC/src/ios/SignalRingRTC/SignalRingRTC/**/*.h'
  s.private_header_files = 'WebRTC/Build/libringrtc/*.h'

  s.vendored_libraries = 'WebRTC/Build/libringrtc/libringrtc.a'

  s.module_map = 'RingRTC/src/ios/SignalRingRTC/SignalRingRTC/SignalRingRTC.modulemap'

  s.dependency 'SignalCoreKit'
  s.dependency 'PromiseKit'

  s.test_spec 'Tests' do |test_spec|
    test_spec.source_files = 'RingRTC/src/ios/SignalRingRTC/SignalRingRTCTests/**/*.{h,m,swift}'
  end

  s.subspec 'WebRTC' do |webrtc|
    webrtc.vendored_frameworks = 'WebRTC/Build/WebRTC.framework'
  end
end
