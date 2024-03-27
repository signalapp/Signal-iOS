//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSDisappearingMessagesJob.h"
#import "AppContext.h"
#import "AppReadiness.h"
#import "ContactsManagerProtocol.h"
#import "NSTimer+OWS.h"
#import "OWSBackgroundTask.h"
#import "OWSDisappearingMessagesConfiguration.h"
#import "TSIncomingMessage.h"
#import "TSMessage.h"
#import "TSThread.h"
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

// Can we move to Signal-iOS?
@interface OWSDisappearingMessagesJob ()

+ (dispatch_queue_t)serialQueue;

// These three properties should only be accessed on the main thread.
@property (nonatomic) BOOL hasStarted;
@property (nonatomic, nullable) NSTimer *nextDisappearanceTimer;
@property (nonatomic, nullable) NSDate *nextDisappearanceDate;
@property (nonatomic, nullable) NSTimer *fallbackTimer;

@end

void AssertIsOnDisappearingMessagesQueue(void);

void AssertIsOnDisappearingMessagesQueue(void)
{
#ifdef DEBUG
    dispatch_assert_queue(OWSDisappearingMessagesJob.serialQueue);
#endif
}

#pragma mark -

@implementation OWSDisappearingMessagesJob

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    // suspenders in case a deletion schedule is missed.
    NSTimeInterval kFallBackTimerInterval = 5 * kMinuteInterval;
    AppReadinessRunNowOrWhenMainAppDidBecomeReadyAsync(^{
        self.fallbackTimer = [NSTimer weakScheduledTimerWithTimeInterval:kFallBackTimerInterval
                                                                  target:self
                                                                selector:@selector(fallbackTimerDidFire)
                                                                userInfo:nil
                                                                 repeats:YES];
    });

    OWSSingletonAssert();

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidBecomeActive:)
                                                 name:OWSApplicationDidBecomeActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillResignActive:)
                                                 name:OWSApplicationWillResignActiveNotification
                                               object:nil];

    return self;
}

+ (dispatch_queue_t)serialQueue
{
    static dispatch_queue_t queue = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("org.signal.disappearing-messages", DISPATCH_QUEUE_SERIAL_WITH_AUTORELEASE_POOL);
    });
    return queue;
}

- (NSInteger)runLoop
{
    AssertIsOnDisappearingMessagesQueue();
    return [self _runLoop];
}

- (void)startAnyExpirationForMessage:(TSMessage *)message
                 expirationStartedAt:(uint64_t)expirationStartedAt
                         transaction:(SDSAnyWriteTransaction *_Nonnull)transaction
{
    OWSAssertDebug(transaction);

    if (!message.shouldStartExpireTimer) {
        return;
    }

    // Don't clobber if multiple actions simultaneously triggered expiration.
    if (message.expireStartedAt == 0 || message.expireStartedAt > expirationStartedAt) {
        [message updateWithExpireStartedAt:expirationStartedAt transaction:transaction];
    }

    [transaction addAsyncCompletionOffMain:^{
        // Necessary that the async expiration run happens *after* the message is saved with it's new
        // expiration configuration.
        [self scheduleRunByDate:[NSDate ows_dateWithMillisecondsSince1970:message.expiresAt]];
    }];
}

- (void)scheduleRunByTimestamp:(uint64_t)timestamp
{
    [self scheduleRunByDate:[NSDate ows_dateWithMillisecondsSince1970:timestamp]];
}

#pragma mark -

- (void)startIfNecessary
{
    AppReadinessRunNowOrWhenAppDidBecomeReadySync(^{
        OWSAssertIsOnMainThread();

        if (self.hasStarted) {
            return;
        }

        if ([[self class] isDatabaseCorrupted]) {
            return;
        }

        self.hasStarted = YES;

        dispatch_async(OWSDisappearingMessagesJob.serialQueue, ^{
            // Theoretically this shouldn't be necessary, but there was a race condition when receiving a backlog
            // of messages across timer changes which could cause a disappearing message's timer to never be started.
            [self cleanUpMessagesWhichFailedToStartExpiringWithSneakyTransaction];
            [self runLoop];
        });
    });
}

#ifdef TESTABLE_BUILD
- (void)syncPassForTests
{
    dispatch_sync(OWSDisappearingMessagesJob.serialQueue, ^{
        [self runLoop];
    });
}
#endif

- (NSDateFormatter *)dateFormatter
{
    static NSDateFormatter *dateFormatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dateFormatter = [NSDateFormatter new];
        dateFormatter.dateStyle = NSDateFormatterNoStyle;
        dateFormatter.timeStyle = NSDateFormatterMediumStyle;
        dateFormatter.locale = [NSLocale systemLocale];
    });

    return dateFormatter;
}

- (void)scheduleRunByDate:(NSDate *)date
{
    OWSAssertDebug(date);

    dispatch_async(dispatch_get_main_queue(), ^{
        if (!CurrentAppContext().isMainAppAndActive) {
            // Don't schedule run when inactive or not in main app.
            return;
        }

        // Don't run more often than once per second.
        const NSTimeInterval kMinDelaySeconds = 1.0;
        NSTimeInterval delaySeconds = MAX(kMinDelaySeconds, date.timeIntervalSinceNow);
        NSDate *newTimerScheduleDate = [NSDate dateWithTimeIntervalSinceNow:delaySeconds];
        if (self.nextDisappearanceDate && [self.nextDisappearanceDate isBeforeDate:newTimerScheduleDate]) {
            return;
        }

        // Update Schedule
        [self resetNextDisappearanceTimer];
        self.nextDisappearanceDate = newTimerScheduleDate;
        self.nextDisappearanceTimer = [NSTimer weakTimerWithTimeInterval:delaySeconds
                                                                  target:self
                                                                selector:@selector(disappearanceTimerDidFire)
                                                                userInfo:nil
                                                                 repeats:NO];
        [[NSRunLoop mainRunLoop] addTimer:self.nextDisappearanceTimer forMode:NSRunLoopCommonModes];
    });
}

- (void)disappearanceTimerDidFire
{
    OWSAssertIsOnMainThread();

    if (!CurrentAppContext().isMainAppAndActive) {
        // Don't schedule run when inactive or not in main app.
        OWSFailDebug(@"Disappearing messages job timer fired while main app inactive.");
        return;
    }

    AppReadinessRunNowOrWhenAppDidBecomeReadyAsync(^{
        [self resetNextDisappearanceTimer];

        dispatch_async(OWSDisappearingMessagesJob.serialQueue, ^{ [self runLoop]; });
    });
}

- (void)fallbackTimerDidFire
{
    OWSAssertIsOnMainThread();

    BOOL recentlyScheduledDisappearanceTimer = NO;
    if (fabs(self.nextDisappearanceDate.timeIntervalSinceNow) < 1.0) {
        recentlyScheduledDisappearanceTimer = YES;
    }

    if (!CurrentAppContext().isMainAppAndActive) {
        return;
    }

    AppReadinessRunNowOrWhenMainAppDidBecomeReadyAsync(^{
        dispatch_async(OWSDisappearingMessagesJob.serialQueue, ^{
            NSInteger deletedCount = [self runLoop];

            // Normally deletions should happen via the disappearanceTimer, to make sure that they're prompt.
            // So, if we're deleting something via this fallback timer, something may have gone wrong. The
            // exception is if we're in close proximity to the disappearanceTimer, in which case a race condition
            // is inevitable.
            if (!recentlyScheduledDisappearanceTimer && deletedCount > 0) {
                OWSFailDebug(@"unexpectedly deleted disappearing messages via fallback timer.");
            }
        });
    });
}

- (void)resetNextDisappearanceTimer
{
    OWSAssertIsOnMainThread();

    [self.nextDisappearanceTimer invalidate];
    self.nextDisappearanceTimer = nil;
    self.nextDisappearanceDate = nil;
}

#pragma mark - Notifications

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    AppReadinessRunNowOrWhenAppDidBecomeReadyAsync(
        ^{ dispatch_async(OWSDisappearingMessagesJob.serialQueue, ^{ [self runLoop]; }); });
}

- (void)applicationWillResignActive:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    [self resetNextDisappearanceTimer];
}

@end

NS_ASSUME_NONNULL_END
