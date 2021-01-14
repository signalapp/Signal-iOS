platform :ios, '11.0'
plugin 'cocoapods-binary'

use_frameworks!

###
# OWS Pods
###

pod 'SwiftProtobuf', "1.7.0"

pod 'SignalCoreKit', git: 'https://github.com/signalapp/SignalCoreKit.git', testspecs: ["Tests"]
# pod 'SignalCoreKit', path: '../SignalCoreKit', testspecs: ["Tests"]

pod 'AxolotlKit', git: 'https://github.com/signalapp/SignalProtocolKit.git', branch: 'master', testspecs: ["Tests"]
# pod 'AxolotlKit', path: '../SignalProtocolKit', testspecs: ["Tests"]

pod 'HKDFKit', git: 'https://github.com/signalapp/HKDFKit.git', testspecs: ["Tests"]
# pod 'HKDFKit', path: '../HKDFKit', testspecs: ["Tests"]

pod 'Curve25519Kit', git: 'https://github.com/signalapp/Curve25519Kit', testspecs: ["Tests"]
# pod 'Curve25519Kit', path: '../Curve25519Kit', testspecs: ["Tests"]

pod 'SignalMetadataKit', git: 'https://github.com/signalapp/SignalMetadataKit', testspecs: ["Tests"]
# pod 'SignalMetadataKit', path: '../SignalMetadataKit', testspecs: ["Tests"]

pod 'blurhash', git: 'https://github.com/signalapp/blurhash', branch: 'signal-master'
# pod 'blurhash', path: '../blurhash'

pod 'SignalServiceKit', path: '.', testspecs: ["Tests"]

pod 'ZKGroup', git: 'https://github.com/signalapp/signal-zkgroup-swift', testspecs: ["Tests"]

pod 'SignalArgon2', git: 'https://github.com/signalapp/Argon2.git', submodules: true, testspecs: ["Tests"]
# pod 'SignalArgon2', path: '../Argon2', testspecs: ["Tests"]

pod 'PromiseKit'

# pod 'GRDB.swift/SQLCipher', path: '../GRDB.swift'
pod 'GRDB.swift/SQLCipher'

pod 'SQLCipher', ">= 4.0.1"

###
# forked third party pods
###

# Forked for performance optimizations that are not likely to be upstreamed as they are specific
# to our limited use of Mantle
pod 'Mantle', git: 'https://github.com/signalapp/Mantle', branch: 'signal-master'
# pod 'Mantle', path: '../Mantle'

# Forked for compatibily with the ShareExtension, changes have an open PR, but have not been merged.
pod 'YapDatabase/SQLCipher', :git => 'https://github.com/signalapp/YapDatabase.git', branch: 'signal-release'
# pod 'YapDatabase/SQLCipher', path: '../YapDatabase'

# Forked to incorporate our self-built binary artifact.
pod 'GRKOpenSSLFramework', git: 'https://github.com/signalapp/GRKOpenSSLFramework', branch: 'mkirk/1.0.2t'
#pod 'GRKOpenSSLFramework', path: '../GRKOpenSSLFramework'

pod 'Starscream', git: 'https://github.com/signalapp/Starscream.git', branch: 'signal-release'
# pod 'Starscream', path: '../Starscream'

pod 'libPhoneNumber-iOS', git: 'https://github.com/signalapp/libPhoneNumber-iOS', branch: 'signal-master'
# pod 'libPhoneNumber-iOS', path: '../libPhoneNumber-iOS'

pod 'YYImage', git: 'https://github.com/signalapp/YYImage', :inhibit_warnings => true
# pod 'YYImage', path: '../YYImage'

###
# third party pods
####

pod 'AFNetworking/NSURLSession', inhibit_warnings: true
pod 'PureLayout', :inhibit_warnings => true
pod 'Reachability', :inhibit_warnings => true
pod 'lottie-ios', :inhibit_warnings => true
pod 'BonMot', inhibit_warnings: true

# For catalyst we need to be on master until 3.6.7 or later is released
pod 'ZXingObjC', git: 'https://github.com/zxingify/zxingify-objc.git', inhibit_warnings: true, binary: true

target 'Signal' do
  # Pods only available inside the main Signal app
  pod 'SSZipArchive', :inhibit_warnings => true
  pod 'SignalRingRTC', path: 'ThirdParty/SignalRingRTC.podspec', inhibit_wranings: true

  target 'SignalTests' do
    inherit! :search_paths
  end

  target 'SignalPerformanceTests' do
    inherit! :search_paths
  end
end

# These extensions inherit all of the pods
target 'SignalShareExtension'
target 'SignalMessaging'
target 'NotificationServiceExtension'

post_install do |installer|
  enable_strip(installer)
  enable_extension_support_for_purelayout(installer)
  configure_warning_flags(installer)
  configure_testable_build(installer)
  disable_bitcode(installer)
  copy_acknowledgements
end

# Works around CocoaPods behavior designed for static libraries.
# See https://github.com/CocoaPods/CocoaPods/issues/10277
def enable_strip(installer)
  installer.pods_project.build_configurations.each do |build_configuration|
    build_configuration.build_settings['STRIP_INSTALLED_PRODUCT'] = 'YES'
  end
end

# PureLayout by default makes use of UIApplication, and must be configured to be built for an extension.
def enable_extension_support_for_purelayout(installer)
  installer.pods_project.targets.each do |target|
    if target.name.end_with? "PureLayout"
      target.build_configurations.each do |build_configuration|
         build_configuration.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= '$(inherited) PURELAYOUT_APP_EXTENSIONS=1'
      end
    end
  end
end

# We want some warning to be treated as errors.
#
# NOTE: We have to manually keep this list in sync with what's in our
# Signal.xcodeproj config in Xcode go to:
#   Signal Project > Build Settings > Other Warning Flags
def configure_warning_flags(installer)
  installer.pods_project.targets.each do |target|
      target.build_configurations.each do |build_configuration|
          build_configuration.build_settings['WARNING_CFLAGS'] = ['$(inherited)',
                                                                  '-Werror=incompatible-pointer-types',
                                                                  '-Werror=protocol',
                                                                  '-Werror=incomplete-implementation',
                                                                  '-Werror=objc-literal-conversion',
                                                                  '-Werror=objc-property-synthesis',
                                                                  '-Werror=objc-protocol-property-synthesis']
      end
  end
end

def configure_testable_build(installer)
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |build_configuration|
      next unless ["Testable Release", "Debug"].include?(build_configuration.name)

      build_configuration.build_settings['OTHER_CFLAGS'] ||= '$(inherited) -DTESTABLE_BUILD'
      build_configuration.build_settings['OTHER_SWIFT_FLAGS'] ||= '$(inherited) -DTESTABLE_BUILD'
      if target.name.end_with? "PureLayout"
        # Avoid overwriting the PURELAYOUT_APP_EXTENSIONS.
      else
       build_configuration.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= '$(inherited) TESTABLE_BUILD=1'
      end
      build_configuration.build_settings['ENABLE_TESTABILITY'] = 'YES'
      build_configuration.build_settings['ONLY_ACTIVE_ARCH'] = 'YES'
    end
  end
end


def disable_bitcode(installer)
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['ENABLE_BITCODE'] = 'NO'
    end
  end
end

def copy_acknowledgements
  raw_acknowledgements = File.read('Pods/Target Support Files/Pods-Signal/Pods-Signal-Acknowledgements.plist')
  formatted_acknowledgements = raw_acknowledgements.gsub(/(?<!>)(?<!\n)\n( *)(?![ \*])(?![ -])(?!\n)(?!<)/, ' ')
  File.open('Signal/Settings.bundle/Acknowledgements.plist', "w") { |file| file.puts formatted_acknowledgements }
end
