platform :ios, '8.0'
source 'https://github.com/CocoaPods/Specs.git'

use_frameworks!

def shared_pods
  # OWS Pods
  # pod 'SQLCipher', path: '../sqlcipher2'
  pod 'SQLCipher', :git => 'https://github.com/sqlcipher/sqlcipher.git', :commit => 'd5c2bec'
  # pod 'YapDatabase/SQLCipher', path: '../YapDatabase'
  pod 'YapDatabase/SQLCipher', :git => 'https://github.com/WhisperSystems/YapDatabase.git', branch: 'release/unencryptedHeaders'
  pod 'AxolotlKit',   path: '../SignalProtocolKit'
  pod 'SignalServiceKit', path: '.'
  # pod 'AxolotlKit', git: 'https://github.com/WhisperSystems/SignalProtocolKit.git', branch: 'mkirk/framework-friendly'
  #pod 'AxolotlKit', path: '../SignalProtocolKit'
  pod 'HKDFKit', git: 'https://github.com/WhisperSystems/HKDFKit.git', branch: 'mkirk/framework-friendly'
  #pod 'HKDFKit', path: '../HKDFKit'
  pod 'Curve25519Kit', git: 'https://github.com/WhisperSystems/Curve25519Kit', branch: 'mkirk/framework-friendly'
  #pod 'Curve25519Kit', path: '../Curve25519Kit'
  pod 'GRKOpenSSLFramework', git: 'https://github.com/WhisperSystems/GRKOpenSSLFramework'
  #pod 'GRKOpenSSLFramework', path: '../GRKOpenSSLFramework'

  # third party pods
  pod 'AFNetworking', inhibit_warnings: true
  pod 'JSQMessagesViewController',  git: 'https://github.com/WhisperSystems/JSQMessagesViewController.git', branch: 'mkirk/share-compatible', :inhibit_warnings => true
  #pod 'JSQMessagesViewController',  git: 'https://github.com/WhisperSystems/JSQMessagesViewController.git', branch: 'signal-master', :inhibit_warnings => true
  #pod 'JSQMessagesViewController',   path: '../JSQMessagesViewController'
  pod 'Mantle', :inhibit_warnings => true
  # pod 'YapDatabase/SQLCipher', :inhibit_warnings => true
  pod 'PureLayout', :inhibit_warnings => true
  pod 'Reachability', :inhibit_warnings => true
  pod 'SocketRocket', :git => 'https://github.com/facebook/SocketRocket.git', :inhibit_warnings => true
  pod 'YYImage'
end

target 'Signal' do
  shared_pods
  pod 'ATAppUpdater', :inhibit_warnings => true
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
  # Disable some asserts when building for tests
  set_building_for_tests_config(installer, 'SignalServiceKit')
  enable_extension_support_for_purelayout(installer)
end

# There are some asserts and debug checks that make testing difficult - e.g. Singleton asserts
def set_building_for_tests_config(installer, target_name)
  target = installer.pods_project.targets.detect { |target| target.to_s == target_name }
  if target == nil
    throw "failed to find target: #{target_name}"
  end

  build_config_name = "Test"
  build_config = target.build_configurations.detect { |config| config.to_s == build_config_name }
  if build_config == nil
    throw "failed to find config: #{build_config_name} for target: #{target_name}"
  end

  puts "--[!] Disabling singleton enforcement for target: #{target} in config: #{build_config}"
  existing_definitions = build_config.build_settings['GCC_PREPROCESSOR_DEFINITIONS']

  if existing_definitions == nil || existing.length == 0
    existing_definitions = "$(inheritied)"
  end
  build_config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] = "#{existing_definitions} POD_CONFIGURATION_TEST=1 COCOAPODS=1 SSK_BUILDING_FOR_TESTS=1"
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

