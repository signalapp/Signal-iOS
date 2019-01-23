platform :ios, '9.0'
source 'https://github.com/CocoaPods/Specs.git'

use_frameworks!

def shared_pods

  ###
  # OWS Pods
  ###

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

  pod 'SignalServiceKit', path: '.', testspecs: ["Tests"]

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

  pod 'Starscream', git: 'git@github.com:signalapp/Starscream.git', branch: 'signal-release'
  # pod 'Starscream', path: '../Starscream'

  ###
  # third party pods
  ####

  pod 'AFNetworking', inhibit_warnings: true
  pod 'PureLayout', :inhibit_warnings => true
  pod 'Reachability', :inhibit_warnings => true
  pod 'YYImage', :inhibit_warnings => true
end

target 'Signal' do
  shared_pods
  pod 'SSZipArchive', :inhibit_warnings => true

  target 'SignalTests' do
    inherit! :search_paths
  end
end

target 'SignalShareExtension' do
  shared_pods
end

target 'SignalMessaging' do
  shared_pods
end

post_install do |installer|
  enable_extension_support_for_purelayout(installer)
end

# PureLayout by default makes use of UIApplication, and must be configured to be built for an extension.
def enable_extension_support_for_purelayout(installer)
  installer.pods_project.targets.each do |target|
    if target.name.end_with? "PureLayout"
      target.build_configurations.each do |build_configuration|
        if build_configuration.build_settings['APPLICATION_EXTENSION_API_ONLY'] == 'YES'
          build_configuration.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] = ['$(inherited)', 'PURELAYOUT_APP_EXTENSIONS=1']
        end
      end
    end
  end
end

