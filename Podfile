platform :ios, '8.0'
source 'https://github.com/CocoaPods/Specs.git'

target 'Signal' do
    pod 'SocketRocket',               :git => 'https://github.com/facebook/SocketRocket.git'
    pod 'AxolotlKit',                 git: 'https://github.com/WhisperSystems/SignalProtocolKit.git'
    #pod 'AxolotlKit',                 path: '../SignalProtocolKit'
    #pod 'SignalServiceKit',           git: 'https://github.com/WhisperSystems/SignalServiceKit.git'
    pod 'SignalServiceKit',           path: '../SignalServiceKit'
    pod 'OpenSSL'
    pod 'JSQMessagesViewController',  git: 'https://github.com/WhisperSystems/JSQMessagesViewController.git', branch: 'mkirk/position-edit-menu'
    #pod 'JSQMessagesViewController'   path: '../JSQMessagesViewController'
    pod 'PureLayout'
    pod 'Reachability'
    target 'SignalTests' do
        inherit! :search_paths
    end
end
