platform :ios, '12.0'
source 'https://github.com/CocoaPods/Specs.git'

use_frameworks!
inhibit_all_warnings!

def shared_pods

  ###
  # OWS Pods
  ###

  pod 'SessionCoreKit', git: 'https://github.com/loki-project/session-ios-core-kit.git', testspecs: ["Tests"] # Fork of SignalCoreKit
  # pod 'SignalCoreKit', path: '../SignalCoreKit', testspecs: ["Tests"]

  pod 'SessionAxolotlKit', git: 'https://github.com/loki-project/session-ios-protocol-kit.git', branch: 'master', testspecs: ["Tests"] # Fork of AxolotlKit
  # pod 'AxolotlKit', path: '../SignalProtocolKit', testspecs: ["Tests"]

  pod 'SessionHKDFKit', git: 'https://github.com/nielsandriesse/session-ios-hkdf-kit.git', testspecs: ["Tests"] # Fork of HKDFKit
  # pod 'HKDFKit', path: '../HKDFKit', testspecs: ["Tests"]

  pod 'SessionCurve25519Kit', git: 'https://github.com/loki-project/session-ios-curve-25519-kit', testspecs: ["Tests"] # Fork of Curve25519Kit
  # pod 'Curve25519Kit', path: '../Curve25519Kit', testspecs: ["Tests"]

  pod 'SessionMetadataKit', git: 'https://github.com/loki-project/session-ios-metadata-kit', testspecs: ["Tests"] # Fork of SignalMetadataKit
  # pod 'SignalMetadataKit', path: '../SignalMetadataKit', testspecs: ["Tests"]

  pod 'SessionServiceKit', path: '.', testspecs: ["Tests"]

  # Project does not compile with PromiseKit 6.7.1
  # see: https://github.com/mxcl/PromiseKit/issues/990
  pod 'PromiseKit', "6.5.3"

  ###
  # forked third party pods
  ###

  # Includes some soon to be released "unencrypted header" changes required for the Share Extension
  pod 'SQLCipher', ">= 4.0.1"

  # Forked for performance optimizations that are not likely to be upstreamed as they are specific
  # to our limited use of Mantle
  pod 'Mantle', git: 'https://github.com/signalapp/Mantle', branch: 'signal-master'
  # pod 'Mantle', path: '../Mantle'

  # Forked for compatibily with the ShareExtension, changes have an open PR, but have not been merged.
  pod 'YapDatabase/SQLCipher', :git => 'https://github.com/signalapp/YapDatabase.git', branch: 'signal-release'
  # pod 'YapDatabase/SQLCipher', path: '../YapDatabase'

  # Forked to incorporate our self-built binary artifact.
  pod 'GRKOpenSSLFramework', git: 'https://github.com/signalapp/GRKOpenSSLFramework'
  #pod 'GRKOpenSSLFramework', path: '../GRKOpenSSLFramework'

  pod 'Starscream', git: 'https://github.com/signalapp/Starscream.git', branch: 'signal-release'
  # pod 'Starscream', path: '../Starscream'

  ###
  # third party pods
  ###

  pod 'AFNetworking', '~> 3.2.1', inhibit_warnings: true
  pod 'PureLayout', '~> 3.1.4', :inhibit_warnings => true
  pod 'Reachability', :inhibit_warnings => true
  pod 'YYImage', git: 'https://github.com/signalapp/YYImage', :inhibit_warnings => true
  pod 'ZXingObjC', '~> 3.6.4', :inhibit_warnings => true
end

target 'Signal' do
  project 'Signal'
  shared_pods
  pod 'SSZipArchive', :inhibit_warnings => true

  ###
  # Loki third party pods
  ###

  pod 'CryptoSwift', '~> 1.3', :inhibit_warnings => true
  pod 'FeedKit', '~> 8.1', :inhibit_warnings => true
  pod 'NVActivityIndicatorView', '~> 4.7', :inhibit_warnings => true
  pod 'Sodium', '~> 0.8.0', :inhibit_warnings => true

  target 'SignalTests' do
    inherit! :search_paths
  end
end

target 'SignalShareExtension' do
  project 'Signal'
  shared_pods
end

target 'LokiPushNotificationService' do
  project 'Signal'
  shared_pods

  ###
  # Loki third party pods
  ###

  pod 'CryptoSwift', '~> 1.3', :inhibit_warnings => true
end

target 'SignalMessaging' do
  project 'Signal'
  shared_pods
end

target 'SessionMessagingKit' do
  pod 'PromiseKit', :inhibit_warnings => true
end

target 'SessionSnodeKit' do
  pod 'CryptoSwift', :inhibit_warnings => true
  pod 'Curve25519Kit', :inhibit_warnings => true
  pod 'PromiseKit', :inhibit_warnings => true
end

target 'SessionUtilities' do
  pod 'PromiseKit', :inhibit_warnings => true
end

post_install do |installer|
  enable_whole_module_optimization_for_cryptoswift(installer)
  enable_extension_support_for_purelayout(installer)
  set_minimum_deployment_target(installer)
end

def enable_whole_module_optimization_for_cryptoswift(installer)
  installer.pods_project.targets.each do |target|
    if target.name.end_with? "CryptoSwift"
      target.build_configurations.each do |config|
        config.build_settings['GCC_OPTIMIZATION_LEVEL'] = 'fast'
        config.build_settings['SWIFT_OPTIMIZATION_LEVEL'] = '-O'
      end
    end
  end
end

# PureLayout by default makes use of UIApplication, and must be configured to be built for an extension.
def enable_extension_support_for_purelayout(installer)
  installer.pods_project.targets.each do |target|
    if target.name.end_with? "PureLayout"
      target.build_configurations.each do |build_configuration|
        if build_configuration.build_settings['APPLICATION_EXTENSION_API_ONLY'] == 'YES'
          build_configuration.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] = [ '$(inherited)', 'PURELAYOUT_APP_EXTENSIONS=1' ]
        end
      end
    end
  end
end

def set_minimum_deployment_target(installer)
    installer.pods_project.targets.each do |target|
        target.build_configurations.each do |build_configuration|
            build_configuration.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '12.0'
        end
    end
end
