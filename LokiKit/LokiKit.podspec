#
#  Be sure to run `pod spec lint LokiKit.podspec' to ensure this is a
#  valid spec and to remove all comments including this before submitting the spec.
#
#  To learn more about Podspec attributes see http://docs.cocoapods.org/specification.html
#  To see working Podspecs in the CocoaPods repo see https://github.com/CocoaPods/Specs/
#

Pod::Spec.new do |s|

  s.name         = "LokiKit"
  s.version      = "0.0.1"
  s.summary      = "A library used to add loki functionality to the messenger"

  s.description  = <<-DESC
  A library used to add loki functionality to the messenger
                   DESC

  s.homepage     = "https://loki.network/"
  s.license      = "GPLv3"
  s.source = { :path => '.' }
  # s.license      = { :type => "MIT", :file => "FILE_LICENSE" }

  s.author             = { "Loki Network" => "team@loki.network" }

  s.platform     = :ios, '9.0'
  s.requires_arc = true
  s.source_files = 'src/**/*.{h,m,mm,swift}'

  # We want to use modules to avoid clobbering CocoaLumberjack macros defined
  # by other OWS modules which *also* import CocoaLumberjack. But because we
  # also use Objective-C++, modules are disabled unless we explicitly enable
  # them

  # s.compiler_flags = "-fcxx-modules"

  # s.prefix_header_file = 'SignalServiceKit/src/TSPrefix.h'
  # s.xcconfig = { 'OTHER_CFLAGS' => '$(inherited) -DSQLITE_HAS_CODEC' }

  # s.resources = ["SignalServiceKit/Resources/Certificates/*"]

  s.dependency 'Curve25519Kit'
  s.dependency 'CryptoSwift'
  s.dependency 'SignalCoreKit'

  s.test_spec 'Tests' do |test_spec|
      test_spec.source_files = 'LokiKitTests/**/*.{h,m,swift}'
  end

end
