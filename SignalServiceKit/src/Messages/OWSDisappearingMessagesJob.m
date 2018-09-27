//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSDisappearingMessagesJob.h"
#import "AppContext.h"
#import "AppReadiness.h"
#import "ContactsManagerProtocol.h"
#import "NSDate+OWS.h"
#import "NSTimer+OWS.h"
#import "OWSBackgroundTask.h"
#import "OWSDisappearingConfigurationUpdateInfoMessage.h"
#import "OWSDisappearingMessagesConfiguration.h"
#import "OWSDisappearingMessagesFinder.h"
#import "OWSPrimaryStorage.h"
#import "TSIncomingMessage.h"
#import "TSMessage.h"
#import "TSThread.h"

NS_ASSUME_NONNULL_BEGIN

// Can we move to Signal-iOS?
@interface OWSDisappearingMessagesJob ()

@property (nonatomic, readonly) YapDatabaseConnection *databaseConnection;

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
    if (@available(iOS 10.0, *)) {
        dispatch_assert_queue(OWSDisappearingMessagesJob.serialQueue);
    }
#endif
}

#pragma mark -

@implementation OWSDisappearingMessagesJob

+ (instancetype)sharedJob
{
    static OWSDisappearingMessagesJob *sharedJob = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedJob = [[self alloc] initWithPrimaryStorage:[OWSPrimaryStorage sharedManager]];
    });
    return sharedJob;
}

- (instancetype)initWithPrimaryStorage:(OWSPrimaryStorage *)primaryStorage
{
    self = [super init];
    if (!self) {
        return self;
    }

    _databaseConnection = primaryStorage.newDatabaseConnection;
    _disappearingMessagesFinder = [OWSDisappearingMessagesFinder new];

    // suspenders in case a deletion schedule is missed.
    NSTimeInterval kFallBackTimerInterval = 5 * kMinuteInterval;
    [AppReadiness runNowOrWhenAppIsReady:^{
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

- (NSUInteger)deleteExpiredMessages
{
    AssertIsOnDisappearingMessagesQueue();

    uint64_t now = [NSDate ows_millisecondTimeStamp];

    OWSBackgroundTask *_Nullable backgroundTask = [OWSBackgroundTask backgroundTaskWithLabelStr:__PRETTY_FUNCTION__];

    __block NSUInteger expirationCount = 0;
    [self.databaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
        [self.disappearingMessagesFinder enumerateExpiredMessagesWithBlock:^(TSMessage *message) {
            // sanity check
            if (message.expiresAt > now) {
                OWSFailDebug(@"Refusing to remove message which doesn't expire until: %lld", message.expiresAt);
                return;
            }

            OWSLogInfo(@"Removing message which expired at: %lld", message.expiresAt);
            [message removeWithTransaction:transaction];
            expirationCount++;
        }
                                                               transaction:transaction];
    }];

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
    [self.databaseConnection readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
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
                         transaction:(YapDatabaseReadWriteTransaction *_Nonnull)transaction
{
    OWSAssertDebug(transaction);

    if (!message.isExpiringMessage) {
        return;
    }

    NSTimeInterval startedSecondsAgo = ([NSDate ows_millisecondTimeStamp] - expirationStartedAt) / 1000.0;
    OWSLogDebug(@"Starting expiration for message read %f seconds ago", startedSecondsAgo);

    // Don't clobber if multiple actions simultaneously triggered expiration.
    if (message.expireStartedAt == 0 || message.expireStartedAt > expirationStartedAt) {
        [message updateWithExpireStartedAt:expirationStartedAt transaction:transaction];
    }

    [transaction addCompletionQueue:nil
                    completionBlock:^{
                        // Necessary that the async expiration run happens *after* the message is saved with it's new
                        // expiration configuration.
                        [self scheduleRunByDate:[NSDate ows_dateWithMillisecondsSince1970:message.expiresAt]];
                    }];
}

- (void)becomeConsistentWithConfigurationForMessage:(TSMessage *)message
                                    contactsManager:(id<ContactsManagerProtocol>)contactsManager
                                        transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    TSThread *thread = [message threadWithTransaction:transaction];
    NSString *remoteContactName = nil;
    if ([message isKindOfClass:[TSIncomingMessage class]]) {
        TSIncomingMessage *incomingMessage = (TSIncomingMessage *)message;
        remoteContactName = [contactsManager displayNameForPhoneIdentifier:incomingMessage.messageAuthorId];
    }

    [self becomeConsistentWithDisappearingDuration:message.expiresInSeconds
                                            thread:thread
                             appearBeforeTimestamp:message.timestampForSorting
                        createdByRemoteContactName:remoteContactName
                            createdInExistingGroup:NO
                                       transaction:transaction];
}

- (void)becomeConsistentWithDisappearingDuration:(uint32_t)duration
                                          thread:(TSThread *)thread
                           appearBeforeTimestamp:(uint64_t)timestampForSorting
                      createdByRemoteContactName:(nullable NSString *)remoteContactName
                          createdInExistingGroup:(BOOL)createdInExistingGroup
                                     transaction:(YapDatabaseReadWriteTransaction *)transaction
{
    OWSAssertDebug(thread);
    OWSAssertDebug(timestampForSorting > 0);
    OWSAssertDebug(transaction);

    OWSBackgroundTask *_Nullable backgroundTask = [OWSBackgroundTask backgroundTaskWithLabelStr:__PRETTY_FUNCTION__];

    // Become eventually consistent in the case that the remote changed their settings at the same time.
    // Also in case remote doesn't support expiring messages
    OWSDisappearingMessagesConfiguration *disappearingMessagesConfiguration =
        [thread disappearingMessagesConfigurationWithTransaction:transaction];

    if (duration == 0) {
        disappearingMessagesConfiguration.enabled = NO;
    } else {
        disappearingMessagesConfiguration.enabled = YES;
        disappearingMessagesConfiguration.durationSeconds = duration;
    }

    if (!disappearingMessagesConfiguration.dictionaryValueDidChange) {
        return;
    }

    OWSLogInfo(@"becoming consistent with disappearing message configuration: %@",
        disappearingMessagesConfiguration.dictionaryValue);

    [disappearingMessagesConfiguration saveWithTransaction:transaction];

    // We want the info message to appear _before_ the message.
    OWSDisappearingConfigurationUpdateInfoMessage *infoMessage =
        [[OWSDisappearingConfigurationUpdateInfoMessage alloc] initWithTimestamp:timestampForSorting - 1
                                                                          thread:thread
                                                                   configuration:disappearingMessagesConfiguration
                                                             createdByRemoteName:remoteContactName
                                                          createdInExistingGroup:createdInExistingGroup];
    [infoMessage saveWithTransaction:transaction];

    OWSAssertDebug(backgroundTask);
    backgroundTask = nil;
}

- (void)startIfNecessary
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.hasStarted) {
            return;
        }
        self.hasStarted = YES;

        dispatch_async(OWSDisappearingMessagesJob.serialQueue, ^{
            // Theoretically this shouldn't be necessary, but there was a race condition when receiving a backlog
            // of messages across timer changes which could cause a disappearing message's timer to never be started.
            [self.databaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
                [self cleanupMessagesWhichFailedToStartExpiringWithTransaction:transaction];
            }];

            [self runLoop];
        });
    });
}

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
        self.nextDisappearanceTimer = [NSTimer weakScheduledTimerWithTimeInterval:delaySeconds
                                                                           target:self
                                                                         selector:@selector(disappearanceTimerDidFire)
                                                                         userInfo:nil
                                                                          repeats:NO];
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

    [self resetNextDisappearanceTimer];

    dispatch_async(OWSDisappearingMessagesJob.serialQueue, ^{
        [self runLoop];
    });
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
}

- (void)resetNextDisappearanceTimer
{
    OWSAssertIsOnMainThread();

    [self.nextDisappearanceTimer invalidate];
    self.nextDisappearanceTimer = nil;
    self.nextDisappearanceDate = nil;
}

#pragma mark - Cleanup

- (void)cleanupMessagesWhichFailedToStartExpiringWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    [self.disappearingMessagesFinder
        enumerateMessagesWhichFailedToStartExpiringWithBlock:^(TSMessage *_Nonnull message) {
            OWSFailDebug(@"starting old timer for message timestamp: %lu", (unsigned long)message.timestamp);

            // We don't know when it was actually read, so assume it was read as soon as it was received.
            uint64_t readTimeBestGuess = message.timestampForSorting;
            [self startAnyExpirationForMessage:message expirationStartedAt:readTimeBestGuess transaction:transaction];
        }
                                                 transaction:transaction];
}

#pragma mark - Notifications

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    [AppReadiness runNowOrWhenAppIsReady:^{
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
