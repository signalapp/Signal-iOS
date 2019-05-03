Pod::Spec.new do |s|

  s.name         = "LokiKit"
  s.version      = "1.0.0"
  s.summary      = "A library containing Loki specific tools used in Session."

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

  s.dependency 'Curve25519Kit'
  s.dependency 'CryptoSwift'
  s.dependency 'SignalCoreKit'

  s.test_spec 'Tests' do |test_spec|
      test_spec.source_files = 'LokiKitTests/**/*.{h,m,swift}'
  end

end
