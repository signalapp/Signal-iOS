platform :ios, '8.0'
source 'https://github.com/CocoaPods/Specs.git'

target 'Signal' do
    pod 'SocketRocket',               :git => 'https://github.com/facebook/SocketRocket.git'
    pod 'AxolotlKit',                 git: 'https://github.com/WhisperSystems/SignalProtocolKit.git'
    #pod 'AxolotlKit',                 path: '../SignalProtocolKit'
    #pod 'SignalServiceKit',           git: 'https://github.com/WhisperSystems/SignalServiceKit.git'
    pod 'SignalServiceKit',           path: '../SignalServiceKit'
    pod 'OpenSSL'
    pod 'PastelogKit',                '~> 1.3'
    pod 'FFCircularProgressView',     '~> 0.5'
    pod 'SCWaveformView',             '~> 1.0'
    pod 'ZXingObjC'
    pod 'JSQMessagesViewController'
    pod 'PureLayout'
    target 'SignalTests' do
        inherit! :search_paths
    end
end
