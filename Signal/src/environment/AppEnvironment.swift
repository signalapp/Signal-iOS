//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import SignalMessaging

@objc public class AppEnvironment : NSObject {
    
    private static var _shared : AppEnvironment = AppEnvironment()
    
    @objc
    public class var shared : AppEnvironment {
        get {
            return _shared
        }
        set {
            _shared = newValue
        }
    }
    
    @objc
    public var callMessageHandler : WebRTCCallMessageHandler
    
    @objc
    public var callService : CallService
    
    @objc
    public var outboundCallInitiator : OutboundCallInitiator
    
    @objc
    public var messageFetcherJob : MessageFetcherJob
    
    @objc
    public var notificationsManager : NotificationsManager
    
    @objc
    public var accountManager : AccountManager
    
    @objc
    public var callNotificationsAdapter : CallNotificationsAdapter
    
    @objc
    public init(callMessageHandler : WebRTCCallMessageHandler,
                callService : CallService,
                outboundCallInitiator : OutboundCallInitiator,
                messageFetcherJob : MessageFetcherJob,
                notificationsManager : NotificationsManager,
                accountManager : AccountManager,
                callNotificationsAdapter : CallNotificationsAdapter)
    {
        self.callMessageHandler = callMessageHandler
        self.callService = callService
        self.outboundCallInitiator = outboundCallInitiator
        self.messageFetcherJob = messageFetcherJob
        self.notificationsManager = notificationsManager
        self.accountManager = accountManager
        self.callNotificationsAdapter = callNotificationsAdapter
        
        super
            .init()
        
        SwiftSingletons.register(self)
        
        setup()
    }
    
    private override init()
    {
        let accountManager = AccountManager()
        let notificationsManager = NotificationsManager()
        let callNotificationsAdapter = CallNotificationsAdapter()
        let callService = CallService()
        let callMessageHandler = WebRTCCallMessageHandler()
        let outboundCallInitiator = OutboundCallInitiator()
        let messageFetcherJob = MessageFetcherJob()
        
        self.callMessageHandler = callMessageHandler
        self.callService = callService
        self.outboundCallInitiator = outboundCallInitiator
        self.messageFetcherJob = messageFetcherJob
        self.notificationsManager = notificationsManager
        self.accountManager = accountManager
        self.callNotificationsAdapter = callNotificationsAdapter
        
        super.init()
        
        SwiftSingletons.register(self)
        
        setup()
    }
    
    private func setup()
    {
        callService.createCallUIAdapter()

        // Hang certain singletons on SSKEnvironment too.
        SSKEnvironment.shared.notificationsManager = notificationsManager
        SSKEnvironment.shared.callMessageHandler = callMessageHandler
    }
}
