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

NS_ASSUME_NONNULL_BEGIN
// Can we move to Signal-iOS?
@interface OWSDisappearingMessagesJob ()

@property (nonatomic, readonly) YapDatabaseConnection *databaseConnection;

@property (nonatomic, readonly) OWSDisappearingMessagesFinder *disappearingMessagesFinder;

// These three properties should only be accessed on the main thread.
@property (nonatomic) BOOL hasStarted;
@property (nonatomic, nullable) NSTimer *timer;
@property (nonatomic, nullable) NSDate *timerScheduleDate;

@end

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

// This method should only be called on the serialQueue.
- (void)run
{
    uint64_t now = [NSDate ows_millisecondTimeStamp];

    OWSBackgroundTask *_Nullable backgroundTask = [OWSBackgroundTask backgroundTaskWithLabelStr:__PRETTY_FUNCTION__];

    __block uint expirationCount = 0;
    [self.databaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
        [self.disappearingMessagesFinder enumerateExpiredMessagesWithBlock:^(TSMessage *message) {
            // sanity check
            if (message.expiresAt > now) {
                OWSFail(
                    @"%@ Refusing to remove message which doesn't expire until: %lld", self.logTag, message.expiresAt);
                return;
            }

            DDLogInfo(@"%@ Removing message which expired at: %lld", self.logTag, message.expiresAt);
            [message removeWithTransaction:transaction];
            expirationCount++;
        }
                                                               transaction:transaction];
    }];

    DDLogDebug(@"%@ Removed %u expired messages", self.logTag, expirationCount);

    backgroundTask = nil;
}

// This method should only be called on the serialQueue.
- (void)runLoop
{
    DDLogVerbose(@"%@ Run", self.logTag);

    [self run];

    uint64_t now = [NSDate ows_millisecondTimeStamp];
    __block NSNumber *nextExpirationTimestampNumber;
    [self.databaseConnection readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        nextExpirationTimestampNumber =
            [self.disappearingMessagesFinder nextExpirationTimestampWithTransaction:transaction];
    }];
    if (!nextExpirationTimestampNumber) {
        // In theory we could kill the loop here. It should resume when the next expiring message is saved,
        // But this is a safeguard for any race conditions that exist while running the job as a new message is saved.
        DDLogDebug(@"%@ No more expiring messages.", self.logTag);
        [self scheduleRunLater];
        return;
    }

    uint64_t nextExpirationAt = [nextExpirationTimestampNumber unsignedLongLongValue];
    [self scheduleRunByDate:[NSDate ows_dateWithMillisecondsSince1970:MAX(nextExpirationAt, now)]];
}

+ (void)setExpirationForMessage:(TSMessage *)message
{
    dispatch_async(self.serialQueue, ^{
        [[self sharedJob] setExpirationForMessage:message];
    });
}

- (void)setExpirationForMessage:(TSMessage *)message
{
    if (!message.isExpiringMessage) {
        return;
    }

    OWSDisappearingMessagesConfiguration *disappearingConfig =
        [OWSDisappearingMessagesConfiguration fetchObjectWithUniqueID:message.uniqueThreadId];

    if (!disappearingConfig.isEnabled) {
        return;
    }

    [self setExpirationForMessage:message expirationStartedAt:[NSDate ows_millisecondTimeStamp]];
}

+ (void)setExpirationForMessage:(TSMessage *)message expirationStartedAt:(uint64_t)expirationStartedAt
{
    dispatch_async(self.serialQueue, ^{
        [[self sharedJob] setExpirationForMessage:message expirationStartedAt:expirationStartedAt];
    });
}

// This method should only be called on the serialQueue.
- (void)setExpirationForMessage:(TSMessage *)message expirationStartedAt:(uint64_t)expirationStartedAt
{
    [self.databaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
        [self setExpirationForMessage:message expirationStartedAt:expirationStartedAt transaction:transaction];
    }];
}

- (void)setExpirationForMessage:(TSMessage *)message
            expirationStartedAt:(uint64_t)expirationStartedAt
                    transaction:(YapDatabaseReadWriteTransaction *_Nonnull)transaction
{
    OWSAssert(transaction);

    if (!message.isExpiringMessage) {
        return;
    }

    int startedSecondsAgo = [NSDate new].timeIntervalSince1970 - expirationStartedAt / 1000.0;
    DDLogDebug(@"%@ Starting expiration for message read %d seconds ago", self.logTag, startedSecondsAgo);

    // Don't clobber if multiple actions simultaneously triggered expiration.
    if (message.expireStartedAt == 0 || message.expireStartedAt > expirationStartedAt) {
        [message updateWithExpireStartedAt:expirationStartedAt transaction:transaction];
    }

    // Necessary that the async expiration run happens *after* the message is saved with expiration configuration.
    [self scheduleRunByDate:[NSDate ows_dateWithMillisecondsSince1970:message.expiresAt]];
}

+ (void)setExpirationsForThread:(TSThread *)thread
{
    dispatch_async(self.serialQueue, ^{
        [[self sharedJob] setExpirationsForThread:thread];
    });
}

// This method should only be called on the serialQueue.
- (void)setExpirationsForThread:(TSThread *)thread
{
    OWSBackgroundTask *_Nullable backgroundTask = [OWSBackgroundTask backgroundTaskWithLabelStr:__PRETTY_FUNCTION__];

    uint64_t now = [NSDate ows_millisecondTimeStamp];
    [self.databaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
        [self.disappearingMessagesFinder
            enumerateUnstartedExpiringMessagesInThread:thread
                                                 block:^(TSMessage *_Nonnull message) {
                                                     DDLogWarn(
                                                         @"%@ Starting expiring message which should have already "
                                                         @"been started.",
                                                         self.logTag);
                                                     // specify "now" in case D.M. have since been disabled, but we have
                                                     // existing unstarted expiring messages that still need to expire.
                                                     [self setExpirationForMessage:message
                                                               expirationStartedAt:now
                                                                       transaction:transaction];
                                                 }
                                           transaction:transaction];
    }];

    backgroundTask = nil;
}

+ (void)becomeConsistentWithConfigurationForMessage:(TSMessage *)message
                                    contactsManager:(id<ContactsManagerProtocol>)contactsManager
{
        [[self sharedJob] becomeConsistentWithConfigurationForMessage:message contactsManager:contactsManager];
}

- (void)becomeConsistentWithConfigurationForMessage:(TSMessage *)message
                                    contactsManager:(id<ContactsManagerProtocol>)contactsManager
{
    OWSAssert(message);
    OWSAssert(contactsManager);

    __block OWSBackgroundTask *_Nullable backgroundTask = [OWSBackgroundTask backgroundTaskWithLabelStr:__PRETTY_FUNCTION__];

    dispatch_async(OWSDisappearingMessagesJob.serialQueue, ^{
        // Become eventually consistent in the case that the remote changed their settings at the same time.
        // Also in case remote doesn't support expiring messages
        OWSDisappearingMessagesConfiguration *disappearingMessagesConfiguration =
            [OWSDisappearingMessagesConfiguration fetchOrCreateDefaultWithThreadId:message.uniqueThreadId];

        BOOL changed = NO;
        if (message.expiresInSeconds == 0) {
            if (disappearingMessagesConfiguration.isEnabled) {
                changed = YES;
                DDLogWarn(@"%@ Received remote message which had no expiration set, disabling our expiration to become "
                          @"consistent.",
                    self.logTag);
                disappearingMessagesConfiguration.enabled = NO;
                [disappearingMessagesConfiguration save];
            }
        } else if (message.expiresInSeconds != disappearingMessagesConfiguration.durationSeconds) {
            changed = YES;
            DDLogInfo(@"%@ Received remote message with different expiration set, updating our expiration to become "
                      @"consistent.",
                self.logTag);
            disappearingMessagesConfiguration.enabled = YES;
            disappearingMessagesConfiguration.durationSeconds = message.expiresInSeconds;
            [disappearingMessagesConfiguration save];
        }

        if (!changed) {
            return;
        }

        if ([message isKindOfClass:[TSIncomingMessage class]]) {
            TSIncomingMessage *incomingMessage = (TSIncomingMessage *)message;
            NSString *contactName = [contactsManager displayNameForPhoneIdentifier:incomingMessage.messageAuthorId];

            // We want the info message to appear _before_ the message.
            [[[OWSDisappearingConfigurationUpdateInfoMessage alloc] initWithTimestamp:message.timestamp - 1
                                                                               thread:message.thread
                                                                        configuration:disappearingMessagesConfiguration
                                                                  createdByRemoteName:contactName] save];
        } else {
            // We want the info message to appear _before_ the message.
            [[[OWSDisappearingConfigurationUpdateInfoMessage alloc] initWithTimestamp:message.timestamp - 1
                                                                               thread:message.thread
                                                                        configuration:disappearingMessagesConfiguration]
                save];
        }

        backgroundTask = nil;
    });
}

- (void)startIfNecessary
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.hasStarted) {
            return;
        }
        self.hasStarted = YES;

        [self scheduleRunNow];
    });
}

- (void)scheduleRunNow
{
    [self scheduleRunByDate:[NSDate new] ignoreMinDelay:YES];
}

- (NSTimeInterval)maxDelaySeconds
{
    // Don't run less often than once per N minutes.
    return 5 * kMinuteInterval;
}

// Waits the maximum amount of time to run again.
- (void)scheduleRunLater
{
    [self scheduleRunByDate:[NSDate dateWithTimeIntervalSinceNow:self.maxDelaySeconds] ignoreMinDelay:YES];
}

- (void)scheduleRunByDate:(NSDate *)date
{
    [self scheduleRunByDate:date ignoreMinDelay:NO];
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

- (void)scheduleRunByDate:(NSDate *)date ignoreMinDelay:(BOOL)ignoreMinDelay
{
    OWSAssert(date);

    dispatch_async(dispatch_get_main_queue(), ^{
        if (!CurrentAppContext().isMainAppAndActive) {
            // Don't schedule run when inactive or not in main app.
            return;
        }

        // Don't run more often than once per second.
        const NSTimeInterval kMinDelaySeconds = ignoreMinDelay ? 0.f : 1.f;
        NSTimeInterval delaySeconds = MAX(kMinDelaySeconds, MIN(self.maxDelaySeconds, date.timeIntervalSinceNow));
        NSDate *newTimerScheduleDate = [NSDate dateWithTimeIntervalSinceNow:delaySeconds];
        if (self.timerScheduleDate && [self.timerScheduleDate isBeforeDate:newTimerScheduleDate]) {
            DDLogVerbose(@"%@ Request to run at %@ (%d sec.) ignored due to earlier scheduled run at %@ (%d sec.)",
                self.logTag,
                [self.dateFormatter stringFromDate:date],
                (int)round(MAX(0, [date timeIntervalSinceDate:[NSDate new]])),
                [self.dateFormatter stringFromDate:self.timerScheduleDate],
                (int)round(MAX(0, [self.timerScheduleDate timeIntervalSinceDate:[NSDate new]])));
            return;
        }

        // Update Schedule
        DDLogVerbose(@"%@ Scheduled run at %@ (%d sec.)",
            self.logTag,
            [self.dateFormatter stringFromDate:newTimerScheduleDate],
            (int)round(MAX(0, [newTimerScheduleDate timeIntervalSinceDate:[NSDate new]])));
        [self resetTimer];
        self.timerScheduleDate = newTimerScheduleDate;
        self.timer = [NSTimer weakScheduledTimerWithTimeInterval:delaySeconds
                                                          target:self
                                                        selector:@selector(timerDidFire)
                                                        userInfo:nil
                                                         repeats:NO];
    });
}

- (void)timerDidFire
{
    OWSAssertIsOnMainThread();
    DDLogDebug(@"%@ in %s", self.logTag, __PRETTY_FUNCTION__);

    if (!CurrentAppContext().isMainAppAndActive) {
        // Don't schedule run when inactive or not in main app.
        OWSFail(@"%@ Disappearing messages job timer fired while main app inactive.", self.logTag);
        return;
    }

    [self resetTimer];

    dispatch_async(OWSDisappearingMessagesJob.serialQueue, ^{
        [self runLoop];
    });
}

- (void)resetTimer
{
    OWSAssertIsOnMainThread();

    [self.timer invalidate];
    self.timer = nil;
    self.timerScheduleDate = nil;
}

#pragma mark - Notifications

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    [AppReadiness runNowOrWhenAppIsReady:^{
        [self scheduleRunNow];
    }];
}

- (void)applicationWillResignActive:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    [self resetTimer];
}

@end

NS_ASSUME_NONNULL_END
