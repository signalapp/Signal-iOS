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

  pod 'SignalMetadataKit', git: 'git@github.com:signalapp/SignalMetadataKit', testspecs: ["Tests"]
  # pod 'SignalMetadataKit', path: '../SignalMetadataKit', testspecs: ["Tests"]

  pod 'SignalServiceKit', path: '.', testspecs: ["Tests"]

  # Project does not compile with PromiseKit 6.7.1
  # see: https://github.com/mxcl/PromiseKit/issues/990
  pod 'PromiseKit', "6.5.3"

  ###
  # forked third party pods
  ###

  # pod 'GRDBCipher', path: '../GRDB.swift'
  pod 'GRDBCipher', git: 'https://github.com/signalapp/GRDB.swift', branch: 'signal-release'

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
end

target 'Signal' do
  shared_pods
  pod 'SSZipArchive', :inhibit_warnings => true

  target 'SignalTests' do
    inherit! :search_paths
  end

  target 'SignalPerformanceTests' do
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
  configure_warning_flags(installer)
  configure_testable_build(installer)
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
                                                                  '-Werror=objc-literal-conversion']
      end
  end
end

def configure_testable_build(installer)
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |build_configuration|
      next unless ["Testable Release", "Debug"].include?(build_configuration.name)
 
      build_configuration.build_settings['OTHER_CFLAGS'] ||= '$(inherited) -DTESTABLE_BUILD'
      build_configuration.build_settings['OTHER_SWIFT_FLAGS'] ||= '$(inherited) -DTESTABLE_BUILD'
      build_configuration.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= '$(inherited) TESTABLE_BUILD=1'
    end
  end
end

