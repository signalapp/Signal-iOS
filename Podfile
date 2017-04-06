platform :ios, '8.0'
source 'https://github.com/CocoaPods/Specs.git'

target 'Signal' do
    pod 'SocketRocket',               :git => 'https://github.com/facebook/SocketRocket.git'
    pod 'AxolotlKit',                 git: 'https://github.com/WhisperSystems/SignalProtocolKit.git'
    #pod 'AxolotlKit',                 path: '../SignalProtocolKit'
    pod 'SignalServiceKit',           git: 'https://github.com/WhisperSystems/SignalServiceKit.git', commit: '60dcadb0d704458728d2b96f24eefc803bd80c92'
    #pod 'SignalServiceKit',           path: '../SignalServiceKit'
    pod 'OpenSSL'
    pod 'SCWaveformView',             '~> 1.0'
    pod 'JSQMessagesViewController'
    pod 'PureLayout'
    target 'SignalTests' do
        inherit! :search_paths
    end
end
