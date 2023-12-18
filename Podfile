platform :ios, '13.0'

use_frameworks!

###
# OWS Pods
###

source 'https://cdn.cocoapods.org/'

pod 'SwiftProtobuf', ">= 1.14.0"

pod 'SignalCoreKit', git: 'https://github.com/signalapp/SignalCoreKit', testspecs: ["Tests"]
# pod 'SignalCoreKit', path: '../SignalCoreKit', testspecs: ["Tests"]

ENV['LIBSIGNAL_FFI_PREBUILD_CHECKSUM'] = '53cf20d6b01b801c5afeb9b9f8fafe4fd2971bc862d2d64939cd7d9c3b776f38'
pod 'LibSignalClient', git: 'https://github.com/signalapp/libsignal-client.git', tag: 'v0.37.0', testspecs: ["Tests"]
# pod 'LibSignalClient', path: '../libsignal-client', testspecs: ["Tests"]

pod 'blurhash', git: 'https://github.com/signalapp/blurhash', branch: 'signal-master'
# pod 'blurhash', path: '../blurhash'

ENV['RINGRTC_PREBUILD_CHECKSUM'] = 'a9f4db4f3c11e10a61a18ad3466a1f3fd0955532601fcd7fe4f8efe358935a05'
pod 'SignalRingRTC', git: 'https://github.com/signalapp/ringrtc', tag: 'v2.35.0', inhibit_warnings: true
# pod 'SignalRingRTC', path: '../ringrtc', testspecs: ["Tests"]

pod 'GRDB.swift/SQLCipher'
# pod 'GRDB.swift/SQLCipher', path: '../GRDB.swift'

pod 'SQLCipher', git: 'https://github.com/signalapp/sqlcipher.git', tag: 'v4.5.5-f_barrierfsync-fts5'
# pod 'SQLCipher', path: '../sqlcipher'

###
# forked third party pods
###

# Forked for performance optimizations that are not likely to be upstreamed as they are specific
# to our limited use of Mantle
pod 'Mantle', git: 'https://github.com/signalapp/Mantle', branch: 'signal-master'
# pod 'Mantle', path: '../Mantle'

pod 'libPhoneNumber-iOS', git: 'https://github.com/signalapp/libPhoneNumber-iOS', branch: 'signal-master'
# pod 'libPhoneNumber-iOS', path: '../libPhoneNumber-iOS'

pod 'YYImage', git: 'https://github.com/signalapp/YYImage', :inhibit_warnings => true
pod 'YYImage/libwebp', git: 'https://github.com/signalapp/YYImage', :inhibit_warnings => true
pod 'libwebp', podspec: './ThirdParty/libwebp.podspec.json'
# pod 'YYImage', path: '../YYImage'
# pod 'YYImage/libwebp', path:'../YYImage'

###
# third party pods
####

pod 'Reachability', :inhibit_warnings => true

def ui_pods
  pod 'BonMot', inhibit_warnings: true
  pod 'PureLayout', :inhibit_warnings => true
  pod 'lottie-ios', :inhibit_warnings => true

  pod 'LibMobileCoin/CoreHTTP', git: 'https://github.com/signalapp/libmobilecoin-ios-artifacts', :commit => '5cd4f39a24d06708d1c19aced8384740689d7f61'
  pod 'MobileCoin/CoreHTTP', git: 'https://github.com/mobilecoinofficial/MobileCoin-Swift', tag: 'v5.0.0'
end

target 'Signal' do
  project 'Signal.xcodeproj', 'Debug' => :debug, 'Release' => :release

  # Pods only available inside the main Signal app
  pod 'SSZipArchive', podspec: 'ThirdParty/SSZipArchive.podspec'
  ui_pods

  target 'SignalTests' do
    inherit! :search_paths
  end

  target 'SignalPerformanceTests' do
    inherit! :search_paths
  end
end

# These extensions inherit all of the common pods

target 'SignalMessaging' do 
  pod 'MobileCoinMinimal', git: 'https://github.com/signalapp/MobileCoin-Swift.git', branch: 'charlesmchen/mobileCoinMinimal', testspecs: ["Tests"]
  # pod 'MobileCoinMinimal', path: '../MobileCoinMinimal', testspecs: ["Tests"]
end

target 'SignalShareExtension' do 
  ui_pods
end

target 'SignalUI' do 
  ui_pods

  target 'SignalUITests' do
    inherit! :search_paths
  end
end

target 'SignalServiceKit' do
  pod 'CocoaLumberjack'
  pod 'SAMKeychain'

  target 'SignalServiceKitTests' do
    inherit! :search_paths
  end
end

target 'SignalNSE' do 
end

post_install do |installer|
  enable_strip(installer)
  enable_extension_support_for_purelayout(installer)
  configure_warning_flags(installer)
  configure_testable_build(installer)
  promote_minimum_supported_version(installer)
  disable_bitcode(installer)
  disable_armv7(installer)
  strip_valid_archs(installer)
  update_frameworks_script(installer)
  disable_non_development_pod_warnings(installer)
  fix_ringrtc_project_symlink(installer)
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

# Xcode 13 dropped support for some older iOS versions. We only need them
# to support our project's minimum version, so let's bump each Pod's min
# version to our min to suppress these warnings.
def promote_minimum_supported_version(installer)
  project_min_version = current_target_definition.platform.deployment_target

  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |build_configuration|
      target_version_string = build_configuration.build_settings['IPHONEOS_DEPLOYMENT_TARGET']
      target_version = Version.create(target_version_string)

      if target_version < project_min_version
        build_configuration.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = project_min_version.version
      end
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
    xcconfig_mod = xcconfig_mod.gsub('VALID_ARCHS[sdk=iphonesimulator*] = x86_64 arm64', '')
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

  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |build_configuration|
      # Only suppress warnings for the debug configuration
      # If we're building for release, continue to display warnings for all projects
      next if build_configuration.name != "Debug"

      next unless non_development_targets.any? do |non_dev_target|
        target.name.include?(non_dev_target.name)
      end

      build_configuration.build_settings['GCC_WARN_INHIBIT_ALL_WARNINGS'] = 'YES'
      build_configuration.build_settings['OTHER_SWIFT_FLAGS'] ||= '$(inherited)'
      build_configuration.build_settings['OTHER_SWIFT_FLAGS'] << ' -suppress-warnings'
    end
  end
end

# Workaround for RingRTC's weird cached artifacts, hopefully temporary
def fix_ringrtc_project_symlink(installer)
  ringrtc_header_ref = installer.pods_project.reference_for_path(installer.sandbox.pod_dir('SignalRingRTC') + 'out/release/libringrtc/ringrtc.h')
  if ringrtc_header_ref.path.start_with?('../') || ringrtc_header_ref.path.start_with?('/') then
    ringrtc_header_ref.path = 'out/release/libringrtc/ringrtc.h'
  end
end

def copy_acknowledgements
  targets = [
    'Signal',
    'SignalMessaging',
    'SignalNSE',
    'SignalPerformanceTests',
    'SignalServiceKit',
    'SignalServiceKitTests',
    'SignalShareExtension',
    'SignalTests',
    'SignalUI',
    'SignalUITests'
  ]
  acknowledgements_files = targets.map do |target|
    "Pods/Target Support Files/Pods-#{target}/Pods-#{target}-Acknowledgements.plist"
  end

  def get_specifier_groups(acknowledgements_files)
    acknowledgements_files.map do |file|
      extract_cmd = ['plutil', '-extract', 'PreferenceSpecifiers', 'json', '-o', '-', file]

      io = IO.popen(extract_cmd, unsetenv_others: true, exception: true)
      result = JSON.parse(io.read)
      io.close
      status = $?
      raise status unless status.exitstatus == 0

      result
    end
  end

  def get_acknowledgements_specifiers(group)
    group[1...-1]
  end

  def write_output_file(specifiers)
    output_file = 'Signal/Settings.bundle/Acknowledgements.plist'
    output_json = JSON.dump(specifiers)
    system('plutil', '-create', 'xml1', output_file, exception: true)
    system('plutil', '-insert', 'PreferenceSpecifiers', '-json', output_json, '-append', output_file, exception: true)
  end

  specifier_groups = get_specifier_groups(acknowledgements_files)

  header_specifier = specifier_groups.first.first
  footer_specifier = specifier_groups.first.last
  all_acknowledgements_specifiers = specifier_groups.flat_map {|g| get_acknowledgements_specifiers(g)}

  cleaned_acknowledgements_specifiers = all_acknowledgements_specifiers
    .uniq {|s| s["Title"]}
    .sort_by {|s| s["Title"].downcase}
  final_specifiers = [header_specifier] + cleaned_acknowledgements_specifiers + [footer_specifier]

  write_output_file(final_specifiers)
end
