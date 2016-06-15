platform :ios, '8.0'
source 'https://github.com/CocoaPods/Specs.git'

target 'Signal' do
    pod 'SocketRocket',               :git => 'https://github.com/WhisperSystems/SocketRocket.git', :branch => 'signal-ios'
    pod 'SignalServiceKit',           :git => 'https://github.com/WhisperSystems/SignalServiceKit.git'
    pod 'OpenSSL',                    '~> 1.0.208'
    pod 'PastelogKit',                '~> 1.3'
    pod 'FFCircularProgressView',     '~> 0.5'
    pod 'SCWaveformView',             '~> 1.0'
    pod 'DJWActionSheet'
    pod 'JSQMessagesViewController',  :git => 'https://github.com/WhisperSystems/JSQMessagesViewController', :branch => 'JSignalQ'
    target 'SignalTests' do
        inherit! :search_paths
    end
end
