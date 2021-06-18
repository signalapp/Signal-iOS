platform :ios, '11.0'
plugin 'cocoapods-binary'

use_frameworks!

###
# OWS Pods
###

source 'https://cdn.cocoapods.org/'

pod 'SwiftProtobuf', ">= 1.14.0"

pod 'SignalCoreKit', git: 'https://github.com/signalapp/SignalCoreKit', testspecs: ["Tests"]
# pod 'SignalCoreKit', path: '../SignalCoreKit', testspecs: ["Tests"]

pod 'SignalClient', git: 'https://github.com/signalapp/libsignal-client.git', testspecs: ["Tests"]
# pod 'SignalClient', path: '../libsignal-client', testspecs: ["Tests"]

pod 'Curve25519Kit', git: 'ssh://git@github.com/signalapp/Curve25519Kit', testspecs: ["Tests"], branch: 'feature/SignalClient-adoption'
# pod 'Curve25519Kit', path: '../Curve25519Kit', testspecs: ["Tests"]

pod 'SignalMetadataKit', git: 'ssh://git@github.com/signalapp/SignalMetadataKit', testspecs: ["Tests"], branch: 'feature/SignalClient-adoption'
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

# Forked to incorporate our self-built binary artifact.
pod 'OpenSSL-Universal', git: 'https://github.com/signalapp/GRKOpenSSLFramework'
# pod 'OpenSSL-Universal', path: '../GRKOpenSSLFramework'

pod 'Starscream', git: 'https://github.com/signalapp/Starscream.git', branch: 'signal-release'
# pod 'Starscream', path: '../Starscream'

pod 'libPhoneNumber-iOS', git: 'https://github.com/signalapp/libPhoneNumber-iOS', branch: 'signal-master'
# pod 'libPhoneNumber-iOS', path: '../libPhoneNumber-iOS'

pod 'YYImage', git: 'https://github.com/signalapp/YYImage', :inhibit_warnings => true
pod 'YYImage/libwebp', git: 'https://github.com/signalapp/YYImage', :inhibit_warnings => true
# pod 'YYImage', path: '../YYImage'
# pod 'YYImage/libwebp', path:'../YYImage'

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

pod 'LibMobileCoin', git: 'https://github.com/signalapp/libmobilecoin-ios-artifacts.git', branch: 'signal/1.1.0'
pod 'MobileCoin', git: 'https://github.com/mobilecoinofficial/MobileCoin-Swift.git', :tag => 'v1.1.0'

target 'Signal' do
  project 'Signal.xcodeproj', 'Debug' => :debug, 'Release' => :release

  # Pods only available inside the main Signal app
  pod 'SSZipArchive', :inhibit_warnings => true
  pod 'SignalRingRTC', path: 'ThirdParty/SignalRingRTC.podspec', inhibit_warnings: true

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
  disable_armv7(installer)
  strip_valid_archs(installer)
  update_frameworks_script(installer)
  disable_non_development_pod_warnings(installer)
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
         build_configuration.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= '$(inherited)'
         build_configuration.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] << ' PURELAYOUT_APP_EXTENSIONS=1'
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
      next unless ["Testable Release", "Debug", "Profiling"].include?(build_configuration.name)
      build_configuration.build_settings['ONLY_ACTIVE_ARCH'] = 'YES'

      next unless ["Testable Release", "Debug"].include?(build_configuration.name)
      build_configuration.build_settings['OTHER_CFLAGS'] ||= '$(inherited)'
      build_configuration.build_settings['OTHER_CFLAGS'] << ' -DTESTABLE_BUILD'

      build_configuration.build_settings['OTHER_SWIFT_FLAGS'] ||= '$(inherited)'
      build_configuration.build_settings['OTHER_SWIFT_FLAGS'] << ' -DTESTABLE_BUILD'
      if target.name.end_with? "PureLayout"
        # Avoid overwriting the PURELAYOUT_APP_EXTENSIONS.
      else
        build_configuration.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= '$(inherited)'
        build_configuration.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] << ' TESTABLE_BUILD=1'
      end
      build_configuration.build_settings['ENABLE_TESTABILITY'] = 'YES'
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

def disable_armv7(installer)
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['EXCLUDED_ARCHS'] = 'armv7'
    end
  end
end

def strip_valid_archs(installer)
  Dir.glob('Pods/Target Support Files/**/*.xcconfig') do |xcconfig_path|
    xcconfig = File.read(xcconfig_path)
    xcconfig_mod = xcconfig.gsub('VALID_ARCHS[sdk=iphoneos*] = arm64', '')
    xcconfig_mod = xcconfig_mod.gsub('VALID_ARCHS[sdk=iphonesimulator*] = x86_64', '')
    File.open(xcconfig_path, "w") { |file| file << xcconfig_mod }
  end
end

#update_framework_scripts updates Pod-Signal-frameworks.sh to fix a bug in the .XCFramework->.framework 
#conversation process, by ensuring symlinks are properly respected in the XCFramework. 
#See https://github.com/CocoaPods/CocoaPods/issues/7587
def update_frameworks_script(installer)
    fw_script = File.read('Pods/Target Support Files/Pods-Signal/Pods-Signal-frameworks.sh')
    fw_script_mod = fw_script.gsub('      lipo -remove "$arch" -output "$binary" "$binary"
', '      realBinary="${binary}"
      if [ -L "${realBinary}" ]; then
        echo "Symlinked..."
        dirname="$(dirname "${realBinary}")"
        realBinary="${dirname}/$(readlink "${realBinary}")"
      fi
      lipo -remove "${arch}" -output "${realBinary}" "${realBinary}" || exit 1')
    File.open('Pods/Target Support Files/Pods-Signal/Pods-Signal-frameworks.sh', "w") { |file| file << fw_script_mod }
end

# Disable warnings on any Pod not currently being modified
def disable_non_development_pod_warnings(installer)
  non_development_targets = installer.pod_targets.select do |target|
    !installer.development_pod_targets.include?(target)
  end

  # ZKGroup is security sensitive and is going to be around for the foreseeable
  # future. Let's always warn for it to keep an eye on the warnings
  # (and also fix the warnings)
  always_warn_names = ['ZKGroup']

  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |build_configuration|
      # Only suppress warnings for the debug configuration
      # If we're building for release, continue to display warnings for all projects
      next if build_configuration.name != "Debug"

      next unless non_development_targets.any? do |non_dev_target|
        target.name.include?(non_dev_target.name)
      end

      next if always_warn_names.any? do |warnable_target_name|
        target.name.include?(warnable_target_name)
      end

      build_configuration.build_settings['GCC_WARN_INHIBIT_ALL_WARNINGS'] = 'YES'
      build_configuration.build_settings['OTHER_SWIFT_FLAGS'] ||= '$(inherited)'
      build_configuration.build_settings['OTHER_SWIFT_FLAGS'] << ' -suppress-warnings'
    end
  end
end

def copy_acknowledgements
  raw_acknowledgements = File.read('Pods/Target Support Files/Pods-Signal/Pods-Signal-Acknowledgements.plist')
  formatted_acknowledgements = raw_acknowledgements.gsub(/(?<!>)(?<!\n)\n( *)(?![ \*])(?![ -])(?!\n)(?!<)/, ' ')
  File.open('Signal/Settings.bundle/Acknowledgements.plist', "w") { |file| file.puts formatted_acknowledgements }
end
