Pod::Spec.new do |s|
  s.name                  = "UICKeyChainStore"
  s.version               = "1.0.6"
  s.summary               = "UICKeyChainStore is a simple wrapper for Keychain on iOS and OS X. Makes using Keychain APIs as easy as NSUserDefaults."
  s.homepage              = "https://github.com/kishikawakatsumi/UICKeyChainStore"
  s.social_media_url      = "https://twitter.com/k_katsumi"
  s.license               = { :type => "MIT", :file => "LICENSE" }
  s.author                = { "kishikawa katsumi" => "kishikawakatsumi@mac.com" }
  s.source                = { :git => "https://github.com/FredericJacobs/UICKeyChainStore.git", :tag => "v#{s.version}" }

  s.ios.deployment_target = "4.3"
  s.osx.deployment_target = "10.6"
  s.requires_arc          = true

  s.source_files          = "Lib/*"
  
  s.framework             = "Security"
end
