
/*
 This class is used for settings friend requests to expired
 This is modelled after `OWSDisappearingMessagesJob`.
 */
@objc(OWSLokiFriendRequestExpireJob)
public final class FriendRequestExpireJob : NSObject {
    private let databaseConnection: YapDatabaseConnection
    private let messageFinder = FriendRequestExpireMessageFinder()
    
    // These properties should only be accessed on the main thread.
    private var hasStarted = false
    private var fallbackTimer: Timer?
    private var nextExpireTimer: Timer?
    private var nextExpireDate: Date?
    
    // Our queue
    fileprivate static let serialQueue = DispatchQueue(label: "network.loki.friendrequest.expire")
    
    /// Create a `FriendRequestExpireJob`.
    /// This will create a auto-running job which will set friend requests to expired.
    ///
    /// - Parameter primaryStorage: The primary storage.
    @objc public init(withPrimaryStorage primaryStorage: OWSPrimaryStorage) {
        databaseConnection = primaryStorage.newDatabaseConnection()
        super.init()
        
        // This makes sure we only ever have one instance of this class
        SwiftSingletons.register(self)
        
        // Setup a timer that runs periodically to check for new friend request messages that will soon expire
        AppReadiness.runNowOrWhenAppDidBecomeReady {
            if CurrentAppContext().isMainApp {
                let fallbackInterval = 5 * kMinuteInterval
                self.fallbackTimer = WeakTimer.scheduledTimer(timeInterval: fallbackInterval, target: self, userInfo: nil, repeats: true) { [weak self] _ in
                    AssertIsOnMainThread()
                    
                    guard let strongSelf = self else { return }
                    
                    strongSelf.timerDidFire(mainTimer: false)
                }
            }
        }

        NotificationCenter.default.addObserver(self, selector: #selector(didBecomeActive), name: .OWSApplicationDidBecomeActive, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(willResignActive), name: .OWSApplicationWillResignActive, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    /// Start the job if we haven't done it yet
    @objc public func startIfNecessary() {
        DispatchQueue.main.async {
            guard !self.hasStarted else { return }
            
            self.hasStarted = true;
            FriendRequestExpireJob.serialQueue.async {
                self.runLoop()
            }
        }
    }
    
    /// The main loop
    private func runLoop() {
        AssertIsOnFriendRequestExpireQueue();
        
        // Expire any messages
        expireMessages()
        
        var nextExpirationTimestamp: UInt64? = nil
        databaseConnection.readWrite { transaction in
            nextExpirationTimestamp = self.messageFinder.nextExpirationTimestamp(with: transaction)
        }
        
        guard let timestamp = nextExpirationTimestamp, let nextExpireDate = NSDate.ows_date(withMillisecondsSince1970: timestamp) as? Date else { return }
        
        // Schedule the next timer
        scheduleRun(by: nextExpireDate)
    }
    
    // Schedule the next timer to run
    private func scheduleRun(by date: Date) {
        DispatchQueue.main.async {
            guard CurrentAppContext().isMainAppAndActive else {
                // Don't schedule run when inactive or not in main app.
                return
            }
            
            let minDelaySeconds: TimeInterval = 1
            let delaySeconds = max(minDelaySeconds, date.timeIntervalSinceNow)
            let newTimerScheduleDate = Date(timeIntervalSinceNow: delaySeconds)
            
            // check that we only set the date if needed
            if let previousDate = self.nextExpireDate, previousDate < date {
                // If the date is later than the one we have stored then just ignore
                return
            }
            
            self.resetNextExpireTimer()
            self.nextExpireDate = newTimerScheduleDate
            self.nextExpireTimer = WeakTimer.scheduledTimer(timeInterval: delaySeconds, target: self, userInfo: nil, repeats: false) { [weak self] _ in
                guard let strongSelf = self else { return }
                
                strongSelf.timerDidFire(mainTimer: true)
            }
        }
    }
    
    // Expire any friend request messages
    private func expireMessages() {
        AssertIsOnFriendRequestExpireQueue()
        let now = NSDate.ows_millisecondTimeStamp()
        
        var backgroundTask: OWSBackgroundTask? = OWSBackgroundTask(label: "\(#function)", completionBlock: { [weak self] status in
            AssertIsOnMainThread()
            
            guard status == .success else { return }
            
            guard let strongSelf = self else { return }
            
            strongSelf.databaseConnection.readWrite { transaction in
                strongSelf.messageFinder.enumurateMessagesPendingExpiration(with: { message in
                    
                    // Sanity check
                    guard message.friendRequestExpiresAt <= now else {
                        owsFailDebug("Refusing to expire friend request which doesn't expire until: \(message.friendRequestExpiresAt)")
                        return;
                    }
                    
                    // Check that we only expire sent friend requests
                    guard message is TSOutgoingMessage && message.isFriendRequest else {
                        // Set message to not expire, so our other logic works correctly
                        message.saveFriendRequestExpires(at: 0, with: transaction)
                        return;
                    }
                    
                    // Loki: Expire the friend request message
                    message.thread.saveFriendRequestStatus(.requestExpired, with: transaction)
                    message.saveFriendRequestStatus(.expired, with: transaction)
                    message.saveFriendRequestExpires(at: 0, with: transaction)
                }, transaction: transaction)
            }
        })
    }
    
    private func resetNextExpireTimer() {
        nextExpireTimer?.invalidate()
        nextExpireTimer = nil
        nextExpireDate = nil
    }
    
    private func timerDidFire(mainTimer: Bool) {
        guard CurrentAppContext().isMainAppAndActive else {
            let infoString = mainTimer ? "Main timer fired while main app is inactive" : "Ignoring fallbacktimer for app which is not main and active."
            Logger.info("[Loki Friend Request Expire Job] \(infoString)")
            return
        }
        
        if (mainTimer) { self.resetNextExpireTimer() }
        
        FriendRequestExpireJob.serialQueue.async {
            self.runLoop()
        }
    }
    
}

// MARK: Events
private extension FriendRequestExpireJob {
    
    @objc func didBecomeActive() {
        AssertIsOnMainThread()
        AppReadiness.runNowOrWhenAppDidBecomeReady {
            FriendRequestExpireJob.serialQueue.async {
                self.runLoop()
            }
        }
    }
    
    @objc func willResignActive() {
        AssertIsOnMainThread()
        resetNextExpireTimer()
    }
    
}

// MARK: Asserts
private extension FriendRequestExpireJob {
    
    func AssertIsOnFriendRequestExpireQueue() {
        #if DEBUG
            guard #available(iOS 10.0, *) else { return }
            dispatchPrecondition(condition: .onQueue(FriendRequestExpireJob.serialQueue))
        #endif
    }
}
