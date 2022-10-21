platform :ios, '13.0'
source 'https://github.com/CocoaPods/Specs.git'

use_frameworks!
inhibit_all_warnings!

# Dependencies to be included in the app and all extensions/frameworks
abstract_target 'GlobalDependencies' do
  pod 'PromiseKit'
  pod 'CryptoSwift'
  # FIXME: If https://github.com/jedisct1/swift-sodium/pull/249 gets resolved then revert this back to the standard pod
  pod 'Sodium', :git => 'https://github.com/oxen-io/session-ios-swift-sodium.git', branch: 'session-build'
  pod 'GRDB.swift/SQLCipher'
  pod 'SQLCipher', '~> 4.5.0' # FIXME: Version 4.5.2 is crashing when access DB settings

  # FIXME: We want to remove this once it's been long enough since the migration to GRDB
  pod 'YapDatabase/SQLCipher', :git => 'https://github.com/oxen-io/session-ios-yap-database.git', branch: 'signal-release'
  pod 'WebRTC-lib'
  pod 'SocketRocket', '~> 0.5.1'
  
  target 'Session' do
    pod 'AFNetworking'
    pod 'Reachability'
    pod 'PureLayout', '~> 3.1.8'
    pod 'NVActivityIndicatorView'
    pod 'YYImage/libwebp', git: 'https://github.com/signalapp/YYImage'
    pod 'ZXingObjC'
    pod 'DifferenceKit'
    
    target 'SessionTests' do
      inherit! :complete
      
      pod 'Quick'
      pod 'Nimble'
    end
  end
  
  # Dependencies to be included only in all extensions/frameworks
  abstract_target 'FrameworkAndExtensionDependencies' do
    pod 'Curve25519Kit', git: 'https://github.com/oxen-io/session-ios-curve-25519-kit.git', branch: 'session-version'
    pod 'SignalCoreKit', git: 'https://github.com/oxen-io/session-ios-core-kit', branch: 'session-version'
    
    target 'SessionNotificationServiceExtension'
    target 'SessionSnodeKit'
    
    # Dependencies that are shared across a number of extensions/frameworks but not all
    abstract_target 'ExtendedDependencies' do
      pod 'AFNetworking'
      pod 'PureLayout', '~> 3.1.8'
      
      target 'SessionShareExtension' do
        pod 'NVActivityIndicatorView'
        pod 'DifferenceKit'
      end
      
      target 'SignalUtilitiesKit' do
        pod 'NVActivityIndicatorView'
        pod 'Reachability'
        pod 'SAMKeychain'
        pod 'SwiftProtobuf', '~> 1.5.0'
        pod 'YYImage/libwebp', git: 'https://github.com/signalapp/YYImage'
        pod 'DifferenceKit'
      end
      
      target 'SessionMessagingKit' do
        pod 'Reachability'
        pod 'SAMKeychain'
        pod 'SwiftProtobuf', '~> 1.5.0'
        pod 'DifferenceKit'
        
        target 'SessionMessagingKitTests' do
          inherit! :complete
          
          pod 'Quick'
          pod 'Nimble'
          
          # Need to include this for the tests because otherwise it won't actually build
          pod 'YYImage/libwebp', git: 'https://github.com/signalapp/YYImage'
        end
      end
      
      target 'SessionUtilitiesKit' do
        pod 'SAMKeychain'
        pod 'YYImage/libwebp', git: 'https://github.com/signalapp/YYImage'
        
        target 'SessionUtilitiesKitTests' do
          inherit! :complete
          
          pod 'Quick'
          pod 'Nimble'
        end
      end
    end
  end
  
  target 'SessionUIKit' do
    pod 'GRDB.swift/SQLCipher'
    pod 'DifferenceKit'
  end
end

# Actions to perform post-install
post_install do |installer|
  enable_whole_module_optimization_for_crypto_swift(installer)
  set_minimum_deployment_target(installer)
  enable_fts5_support(installer)
end

def enable_whole_module_optimization_for_crypto_swift(installer)
  installer.pods_project.targets.each do |target|
    if target.name.end_with? "CryptoSwift"
      target.build_configurations.each do |config|
        config.build_settings['GCC_OPTIMIZATION_LEVEL'] = 'fast'
        config.build_settings['SWIFT_OPTIMIZATION_LEVEL'] = '-O'
      end
    end
  end
end

def set_minimum_deployment_target(installer)
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |build_configuration|
      build_configuration.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '13.0'
    end
  end
end

# This is to ensure we enable support for FastTextSearch5 (might not be enabled by default)
# For more info see https://github.com/groue/GRDB.swift/blob/master/Documentation/FullTextSearch.md#enabling-fts5-support
def enable_fts5_support(installer)
  installer.pods_project.targets.select { |target| target.name == "GRDB.swift" }.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['OTHER_SWIFT_FLAGS'] = "$(inherited) -D SQLITE_ENABLE_FTS5"
    end
  end
end
