#
# Be sure to run `pod lib lint SignalRingRTC.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = "SignalRingRTC"
  s.version          = "2.21.0"
  s.summary          = "A Swift & Objective-C library used by the Signal iOS app for WebRTC interactions."

  s.description      = <<-DESC
    A Swift & Objective-C library used by the Signal iOS app for WebRTC interactions."
  DESC

  s.license          = 'GPLv3'
  s.homepage         = 'https://github.com/signalapp/ringrtc'
  s.source           = { git: 'https://github.com/signalapp/ringrtc.git', tag: "v#{s.version.to_s}" }
  s.author           = { 'iOS Team': 'ios@signal.org' }
  s.social_media_url = 'https://twitter.com/signalapp'

  s.platform     = :ios, '12.2'
  s.requires_arc = true

  s.source_files  = 'RingRTC/src/ios/SignalRingRTC/SignalRingRTC/**/*.{h,m,swift}', 'WebRTC/Build/libringrtc/**/*.h'
  s.public_header_files = 'RingRTC/src/ios/SignalRingRTC/SignalRingRTC/**/*.h'
  s.private_header_files = 'WebRTC/Build/libringrtc/*.h'

  s.module_map = 'RingRTC/src/ios/SignalRingRTC/SignalRingRTC/SignalRingRTC.modulemap'

  s.preserve_paths = 'WebRTC/Build/libringrtc/*/libringrtc.a'

  s.dependency 'SignalCoreKit'

  s.pod_target_xcconfig = {
    # Make sure we link the static library, not a dynamic one.
    # Use an extra level of indirection because CocoaPods messes with OTHER_LDFLAGS too.
    'LIBRINGRTC_IF_NEEDED' => '$(PODS_TARGET_SRCROOT)/WebRTC/Build/libringrtc/$(CARGO_BUILD_TARGET)/libringrtc.a',
    'OTHER_LDFLAGS' => '$(LIBRINGRTC_IF_NEEDED)',

    'CARGO_BUILD_TARGET[sdk=iphonesimulator*][arch=arm64]' => 'aarch64-apple-ios-sim',
    'CARGO_BUILD_TARGET[sdk=iphonesimulator*][arch=*]' => 'x86_64-apple-ios',
    'CARGO_BUILD_TARGET[sdk=iphoneos*]' => 'aarch64-apple-ios',
    # Presently, there's no special SDK or arch for maccatalyst,
    # so we need to hackily use the "IS_MACCATALYST" build flag
    # to set the appropriate cargo target
    'CARGO_BUILD_TARGET_MAC_CATALYST_ARM_' => 'aarch64-apple-darwin',
    'CARGO_BUILD_TARGET_MAC_CATALYST_ARM_YES' => 'aarch64-apple-ios-macabi',
    'CARGO_BUILD_TARGET[sdk=macosx*][arch=arm64]' => '$(CARGO_BUILD_TARGET_MAC_CATALYST_ARM_$(IS_MACCATALYST))',
    'CARGO_BUILD_TARGET_MAC_CATALYST_X86_' => 'x86_64-apple-darwin',
    'CARGO_BUILD_TARGET_MAC_CATALYST_X86_YES' => 'x86_64-apple-ios-macabi',
    'CARGO_BUILD_TARGET[sdk=macosx*][arch=*]' => '$(CARGO_BUILD_TARGET_MAC_CATALYST_X86_$(IS_MACCATALYST))',
  }

  s.test_spec 'Tests' do |test_spec|
    test_spec.source_files = 'RingRTC/src/ios/SignalRingRTC/SignalRingRTCTests/**/*.{h,m,swift}'
  end

  s.subspec 'WebRTC' do |webrtc|
    webrtc.vendored_frameworks = 'WebRTC/Build/WebRTC.xcframework'
  end
end
