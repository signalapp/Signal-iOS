//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSDisappearingMessagesJob.h"
#import "AppContext.h"
#import "AppReadiness.h"
#import "ContactsManagerProtocol.h"
#import "NSTimer+OWS.h"
#import "OWSBackgroundTask.h"
#import "OWSDisappearingMessagesConfiguration.h"
#import "OWSDisappearingMessagesFinder.h"
#import "SSKEnvironment.h"
#import "TSIncomingMessage.h"
#import "TSMessage.h"
#import "TSThread.h"
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

// Can we move to Signal-iOS?
@interface OWSDisappearingMessagesJob ()

@property (nonatomic, readonly) OWSDisappearingMessagesFinder *disappearingMessagesFinder;

+ (dispatch_queue_t)serialQueue;

// These three properties should only be accessed on the main thread.
@property (nonatomic) BOOL hasStarted;
@property (nonatomic, nullable) NSTimer *nextDisappearanceTimer;
@property (nonatomic, nullable) NSDate *nextDisappearanceDate;
@property (nonatomic, nullable) NSTimer *fallbackTimer;

@end

void AssertIsOnDisappearingMessagesQueue()
{
#ifdef DEBUG
    dispatch_assert_queue(OWSDisappearingMessagesJob.serialQueue);
#endif
}

#pragma mark -

@implementation OWSDisappearingMessagesJob

+ (instancetype)sharedJob
{
    OWSAssertDebug(SSKEnvironment.shared.disappearingMessagesJob);

    return SSKEnvironment.shared.disappearingMessagesJob;
}

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    _disappearingMessagesFinder = [OWSDisappearingMessagesFinder new];

    // suspenders in case a deletion schedule is missed.
    NSTimeInterval kFallBackTimerInterval = 5 * kMinuteInterval;
    [AppReadiness runNowOrWhenAppDidBecomeReadyPolite:^{
        if (CurrentAppContext().isMainApp) {
            self.fallbackTimer = [NSTimer weakScheduledTimerWithTimeInterval:kFallBackTimerInterval
                                                                      target:self
                                                                    selector:@selector(fallbackTimerDidFire)
                                                                    userInfo:nil
                                                                     repeats:YES];
        }
    }];

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

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

+ (dispatch_queue_t)serialQueue
{
    static dispatch_queue_t queue = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("org.whispersystems.disappearing.messages", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

#pragma mark - Dependencies

- (id<ContactsManagerProtocol>)contactsManager
{
    return SSKEnvironment.shared.contactsManager;
}

- (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
}

#pragma mark -

- (NSUInteger)deleteExpiredMessages
{
    AssertIsOnDisappearingMessagesQueue();

    OWSBackgroundTask *_Nullable backgroundTask = [OWSBackgroundTask backgroundTaskWithLabelStr:__PRETTY_FUNCTION__];

    __block NSUInteger expirationCount = 0;
    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
        [self.disappearingMessagesFinder enumerateExpiredMessagesWithBlock:^(TSMessage *message) {
            // We want to compute `now` *after* our finder fetches results.
            // Otherwise, if we computed it before the finder, and a message had expired in the tiny
            // gap between that computation and when the finder runs, we would skip deleting an
            // expired message until the next expiration run.
            uint64_t now = [NSDate ows_millisecondTimeStamp];

            // sanity check
            if (message.expiresAt > now) {
                OWSFailDebug(@"Refusing to remove message which doesn't expire until: %llu, now: %lld", message.expiresAt, now);
                return;
            }

            OWSLogInfo(@"Removing message which expired at: %lld", message.expiresAt);
            [message anyRemoveWithTransaction:transaction];
            expirationCount++;
        }
                                                               transaction:transaction];
    });

    OWSLogDebug(@"Removed %lu expired messages", (unsigned long)expirationCount);

    OWSAssertDebug(backgroundTask);
    backgroundTask = nil;
    return expirationCount;
}

// deletes any expired messages and schedules the next run.
- (NSUInteger)runLoop
{
    OWSLogVerbose(@"in runLoop");
    AssertIsOnDisappearingMessagesQueue();

    NSUInteger deletedCount = [self deleteExpiredMessages];

    __block NSNumber *nextExpirationTimestampNumber;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
        nextExpirationTimestampNumber =
            [self.disappearingMessagesFinder nextExpirationTimestampWithTransaction:transaction];
    }];

    if (!nextExpirationTimestampNumber) {
        OWSLogDebug(@"No more expiring messages.");
        return deletedCount;
    }

    uint64_t nextExpirationAt = nextExpirationTimestampNumber.unsignedLongLongValue;
    NSDate *nextEpirationDate = [NSDate ows_dateWithMillisecondsSince1970:nextExpirationAt];
    [self scheduleRunByDate:nextEpirationDate];

    return deletedCount;
}

- (void)startAnyExpirationForMessage:(TSMessage *)message
                 expirationStartedAt:(uint64_t)expirationStartedAt
                         transaction:(SDSAnyWriteTransaction *_Nonnull)transaction
{
    OWSAssertDebug(transaction);

    if (!message.shouldStartExpireTimer) {
        return;
    }

    NSTimeInterval startedSecondsAgo = ([NSDate ows_millisecondTimeStamp] - expirationStartedAt) / 1000.0;
    OWSLogDebug(@"Starting expiration for message read %f seconds ago", startedSecondsAgo);

    // Don't clobber if multiple actions simultaneously triggered expiration.
    if (message.expireStartedAt == 0 || message.expireStartedAt > expirationStartedAt) {
        [message updateWithExpireStartedAt:expirationStartedAt transaction:transaction];
    }

    [transaction addAsyncCompletion:^{
        // Necessary that the async expiration run happens *after* the message is saved with it's new
        // expiration configuration.
        [self scheduleRunByDate:[NSDate ows_dateWithMillisecondsSince1970:message.expiresAt]];
    }];
}

#pragma mark -

- (void)startIfNecessary
{
    [AppReadiness runNowOrWhenAppDidBecomeReady:^{
        OWSAssertIsOnMainThread();

        if (self.hasStarted) {
            return;
        }
        self.hasStarted = YES;

        dispatch_async(OWSDisappearingMessagesJob.serialQueue, ^{
            // Theoretically this shouldn't be necessary, but there was a race condition when receiving a backlog
            // of messages across timer changes which could cause a disappearing message's timer to never be started.
            DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
                [self cleanupMessagesWhichFailedToStartExpiringWithTransaction:transaction];
            });
            
            [self runLoop];
        });
    }];
}

- (void)schedulePass
{
    [AppReadiness runNowOrWhenAppDidBecomeReadyPolite:^{
        dispatch_async(OWSDisappearingMessagesJob.serialQueue, ^{ [self runLoop]; });
    }];
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
        dateFormatter.timeStyle = kCFDateFormatterMediumStyle;
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
            OWSLogVerbose(@"Request to run at %@ (%d sec.) ignored due to earlier scheduled run at %@ (%d sec.)",
                [self.dateFormatter stringFromDate:date],
                (int)round(MAX(0, [date timeIntervalSinceDate:[NSDate new]])),
                [self.dateFormatter stringFromDate:self.nextDisappearanceDate],
                (int)round(MAX(0, [self.nextDisappearanceDate timeIntervalSinceDate:[NSDate new]])));
            return;
        }

        // Update Schedule
        OWSLogVerbose(@"Scheduled run at %@ (%d sec.)",
            [self.dateFormatter stringFromDate:newTimerScheduleDate],
            (int)round(MAX(0, [newTimerScheduleDate timeIntervalSinceDate:[NSDate new]])));
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
    OWSLogDebug(@"");

    if (!CurrentAppContext().isMainAppAndActive) {
        // Don't schedule run when inactive or not in main app.
        OWSFailDebug(@"Disappearing messages job timer fired while main app inactive.");
        return;
    }

    [AppReadiness runNowOrWhenAppDidBecomeReadyPolite:^{
        [self resetNextDisappearanceTimer];

        dispatch_async(OWSDisappearingMessagesJob.serialQueue, ^{ [self runLoop]; });
    }];
}

- (void)fallbackTimerDidFire
{
    OWSAssertIsOnMainThread();
    OWSLogDebug(@"");

    BOOL recentlyScheduledDisappearanceTimer = NO;
    if (fabs(self.nextDisappearanceDate.timeIntervalSinceNow) < 1.0) {
        recentlyScheduledDisappearanceTimer = YES;
    }

    if (!CurrentAppContext().isMainAppAndActive) {
        OWSLogInfo(@"Ignoring fallbacktimer for app which is not main and active.");
        return;
    }

    [AppReadiness runNowOrWhenAppDidBecomeReadyPolite:^{
        dispatch_async(OWSDisappearingMessagesJob.serialQueue, ^{
            NSUInteger deletedCount = [self runLoop];

            // Normally deletions should happen via the disappearanceTimer, to make sure that they're prompt.
            // So, if we're deleting something via this fallback timer, something may have gone wrong. The
            // exception is if we're in close proximity to the disappearanceTimer, in which case a race condition
            // is inevitable.
            if (!recentlyScheduledDisappearanceTimer && deletedCount > 0) {
                OWSFailDebug(@"unexpectedly deleted disappearing messages via fallback timer.");
            }
        });
    }];
}

- (void)resetNextDisappearanceTimer
{
    OWSAssertIsOnMainThread();

    [self.nextDisappearanceTimer invalidate];
    self.nextDisappearanceTimer = nil;
    self.nextDisappearanceDate = nil;
}

#pragma mark - Cleanup

- (void)cleanupMessagesWhichFailedToStartExpiringWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    NSMutableArray<NSString *> *messageIds = [NSMutableArray new];
    [self.disappearingMessagesFinder
        enumerateMessagesWhichFailedToStartExpiringWithBlock:^(TSMessage *message, BOOL *stop) {
            OWSFailDebug(@"starting old timer for message timestamp: %llu", message.timestamp);

            [messageIds addObject:message.uniqueId];
        }
                                                 transaction:transaction];

    for (NSString *messageId in messageIds) {
        TSMessage *_Nullable message = [TSMessage anyFetchMessageWithUniqueId:messageId transaction:transaction];
        if (message == nil) {
            OWSFailDebug(@"Missing message.");
            continue;
        }

        // We don't know when it was actually read, so assume it was read as soon as it was received.
        uint64_t readTimeBestGuess = message.receivedAtTimestamp;
        [self startAnyExpirationForMessage:message expirationStartedAt:readTimeBestGuess transaction:transaction];
    }
}

#pragma mark - Notifications

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    [AppReadiness runNowOrWhenAppDidBecomeReadyPolite:^{
        dispatch_async(OWSDisappearingMessagesJob.serialQueue, ^{
            [self runLoop];
        });
    }];
}

- (void)applicationWillResignActive:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    [self resetNextDisappearanceTimer];
}

@end

NS_ASSUME_NONNULL_END
