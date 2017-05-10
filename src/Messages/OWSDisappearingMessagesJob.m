//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSDisappearingMessagesJob.h"
#import "ContactsManagerProtocol.h"
#import "NSDate+millisecondTimeStamp.h"
#import "NSTimer+OWS.h"
#import "OWSDisappearingConfigurationUpdateInfoMessage.h"
#import "OWSDisappearingMessagesConfiguration.h"
#import "OWSDisappearingMessagesFinder.h"
#import "TSIncomingMessage.h"
#import "TSMessage.h"
#import "TSStorageManager.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSDisappearingMessagesJob ()

// This property should only be accessed on the serialQueue.
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
        sharedJob = [[self alloc] initWithStorageManager:[TSStorageManager sharedManager]];
    });
    return sharedJob;
}

- (instancetype)initWithStorageManager:(TSStorageManager *)storageManager
{
    self = [super init];
    if (!self) {
        return self;
    }

    _disappearingMessagesFinder = [[OWSDisappearingMessagesFinder alloc] initWithStorageManager:storageManager];

    OWSSingletonAssert();

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidBecomeActive:)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillResignActive:)
                                                 name:UIApplicationWillResignActiveNotification
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

- (void)run
{
    uint64_t now = [NSDate ows_millisecondTimeStamp];

    __block uint expirationCount = 0;
    [self.disappearingMessagesFinder enumerateExpiredMessagesWithBlock:^(TSMessage *message) {
        // sanity check
        if (message.expiresAt > now) {
            DDLogError(@"%@ Refusing to remove message which doesn't expire until: %lld", self.tag, message.expiresAt);
            return;
        }

        DDLogDebug(@"%@ Removing message which expired at: %lld", self.tag, message.expiresAt);
        [message remove];
        expirationCount++;
    }];

    DDLogDebug(@"%@ Removed %u expired messages", self.tag, expirationCount);
}

- (void)runLoop
{
    DDLogVerbose(@"%@ Run", self.tag);

    [self run];

    uint64_t now = [NSDate ows_millisecondTimeStamp];
    NSNumber *nextExpirationTimestampNumber = [self.disappearingMessagesFinder nextExpirationTimestamp];
    if (!nextExpirationTimestampNumber) {
        // In theory we could kill the loop here. It should resume when the next expiring message is saved,
        // But this is a safeguard for any race conditions that exist while running the job as a new message is saved.
        DDLogDebug(@"%@ No more expiring messages.", self.tag);
        [self runLater];
        return;
    }

    uint64_t nextExpirationAt = [nextExpirationTimestampNumber unsignedLongLongValue];
    [self runByDate:[NSDate ows_dateWithMillisecondsSince1970:MAX(nextExpirationAt, now)]];
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

- (void)setExpirationForMessage:(TSMessage *)message expirationStartedAt:(uint64_t)expirationStartedAt
{
    if (!message.isExpiringMessage) {
        return;
    }

    int startedSecondsAgo = [NSDate new].timeIntervalSince1970 - expirationStartedAt / 1000.0;
    DDLogDebug(@"%@ Starting expiration for message read %d seconds ago", self.tag, startedSecondsAgo);

    // Don't clobber if multiple actions simultaneously triggered expiration.
    if (message.expireStartedAt == 0 || message.expireStartedAt > expirationStartedAt) {
        message.expireStartedAt = expirationStartedAt;
        [message save];
    }

    // Necessary that the async expiration run happens *after* the message is saved with expiration configuration.
    [self runByDate:[NSDate ows_dateWithMillisecondsSince1970:message.expiresAt]];
}

+ (void)setExpirationsForThread:(TSThread *)thread
{
    dispatch_async(self.serialQueue, ^{
        [[self sharedJob] setExpirationsForThread:thread];
    });
}

- (void)setExpirationsForThread:(TSThread *)thread
{
    uint64_t now = [NSDate ows_millisecondTimeStamp];
    [self.disappearingMessagesFinder
        enumerateUnstartedExpiringMessagesInThread:thread
                                             block:^(TSMessage *_Nonnull message) {
                                                 DDLogWarn(@"%@ Starting expiring message which should have already "
                                                           @"been started.",
                                                     self.tag);
                                                 // specify "now" in case D.M. have since been disabled, but we have
                                                 // existing unstarted expiring messages that still need to expire.
                                                 [self setExpirationForMessage:message expirationStartedAt:now];
                                             }];
}

+ (void)becomeConsistentWithConfigurationForMessage:(TSMessage *)message
                                    contactsManager:(id<ContactsManagerProtocol>)contactsManager
{
    dispatch_async(self.serialQueue, ^{
        [[self sharedJob] becomeConsistentWithConfigurationForMessage:message contactsManager:contactsManager];
    });
}

- (void)becomeConsistentWithConfigurationForMessage:(TSMessage *)message
                                    contactsManager:(id<ContactsManagerProtocol>)contactsManager
{
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
                self.tag);
            disappearingMessagesConfiguration.enabled = NO;
            [disappearingMessagesConfiguration save];
        }
    } else if (message.expiresInSeconds != disappearingMessagesConfiguration.durationSeconds) {
        changed = YES;
        DDLogInfo(
            @"%@ Received remote message with different expiration set, updating our expiration to become consistent.",
            self.tag);
        disappearingMessagesConfiguration.enabled = YES;
        disappearingMessagesConfiguration.durationSeconds = message.expiresInSeconds;
        [disappearingMessagesConfiguration save];
    }

    if (!changed) {
        return;
    }

    if ([message isKindOfClass:[TSIncomingMessage class]]) {
        TSIncomingMessage *incomingMessage = (TSIncomingMessage *)message;
        NSString *contactName = [contactsManager displayNameForPhoneIdentifier:incomingMessage.authorId];

        [[[OWSDisappearingConfigurationUpdateInfoMessage alloc] initWithTimestamp:message.timestamp
                                                                           thread:message.thread
                                                                    configuration:disappearingMessagesConfiguration
                                                              createdByRemoteName:contactName] save];
    } else {
        [[[OWSDisappearingConfigurationUpdateInfoMessage alloc] initWithTimestamp:message.timestamp
                                                                           thread:message.thread
                                                                    configuration:disappearingMessagesConfiguration]
            save];
    }
}

- (void)startIfNecessary
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.hasStarted) {
            return;
        }
        self.hasStarted = YES;

        [self runNow];
    });
}

- (void)runNow
{
    [self runByDate:[NSDate new] ignoreMinDelay:YES];
}

- (NSTimeInterval)maxDelaySeconds
{
    // Don't run less often than once per N minutes.
    return 5 * 60.f;
}

// Waits the maximum amount of time to run again.
- (void)runLater
{
    [self runByDate:[NSDate dateWithTimeIntervalSinceNow:self.maxDelaySeconds] ignoreMinDelay:YES];
}

- (void)runByDate:(NSDate *)date
{
    [self runByDate:date ignoreMinDelay:NO];
}

- (void)runByDate:(NSDate *)date ignoreMinDelay:(BOOL)ignoreMinDelay
{
    OWSAssert(date);

    dispatch_async(dispatch_get_main_queue(), ^{
        if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) {
            // Don't schedule run when inactive.
            return;
        }

        NSDateFormatter *dateFormatter = [NSDateFormatter new];
        dateFormatter.dateStyle = NSDateFormatterNoStyle;
        dateFormatter.timeStyle = kCFDateFormatterMediumStyle;

        // Don't run more often than once per second.
        const NSTimeInterval kMinDelaySeconds = ignoreMinDelay ? 0.f : 1.f;
        NSTimeInterval delaySeconds
            = MAX(kMinDelaySeconds, MIN(self.maxDelaySeconds, [date timeIntervalSinceDate:[NSDate new]]));
        NSDate *timerScheduleDate = [NSDate dateWithTimeIntervalSinceNow:delaySeconds];
        if (self.timerScheduleDate && [timerScheduleDate timeIntervalSinceDate:self.timerScheduleDate] > 0) {
            DDLogVerbose(@"%@ Request to run at %@ (%d sec.) ignored due to scheduled run at %@ (%d sec.)",
                self.tag,
                [dateFormatter stringFromDate:date],
                (int)round(MAX(0, [date timeIntervalSinceDate:[NSDate new]])),
                [dateFormatter stringFromDate:self.timerScheduleDate],
                (int)round(MAX(0, [self.timerScheduleDate timeIntervalSinceDate:[NSDate new]])));
            return;
        }

        // Update Schedule
        DDLogVerbose(@"%@ Scheduled run at %@ (%d sec.)",
            self.tag,
            [dateFormatter stringFromDate:timerScheduleDate],
            (int)round(MAX(0, [timerScheduleDate timeIntervalSinceDate:[NSDate new]])));
        [self resetTimer];
        self.timerScheduleDate = timerScheduleDate;
        self.timer = [NSTimer weakScheduledTimerWithTimeInterval:delaySeconds
                                                          target:self
                                                        selector:@selector(timerDidFire)
                                                        userInfo:nil
                                                         repeats:NO];
    });
}

- (void)timerDidFire
{
    OWSAssert([NSThread isMainThread]);

    if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) {
        // Don't run when inactive.
        OWSAssert(0);
        return;
    }

    [self resetTimer];

    dispatch_async(OWSDisappearingMessagesJob.serialQueue, ^{
        [self runLoop];
    });
}

- (void)resetTimer
{
    OWSAssert([NSThread isMainThread]);

    [self.timer invalidate];
    self.timer = nil;
    self.timerScheduleDate = nil;
}

#pragma mark - Notifications

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    OWSAssert([NSThread isMainThread]);

    [self runNow];
}

- (void)applicationWillResignActive:(NSNotification *)notification
{
    OWSAssert([NSThread isMainThread]);

    [self resetTimer];
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end

NS_ASSUME_NONNULL_END
