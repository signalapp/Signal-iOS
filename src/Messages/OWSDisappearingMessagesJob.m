//  Created by Michael Kirk on 9/23/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSDisappearingMessagesJob.h"
#import "NSDate+millisecondTimeStamp.h"
#import "OWSDisappearingMessagesConfiguration.h"
#import "OWSDisappearingMessagesFinder.h"
#import "TSMessage.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSDisappearingMessagesJob ()

@property (nonatomic, readonly) OWSDisappearingMessagesFinder *disappearingMessagesFinder;
@property (atomic) uint64_t scheduledAt;

@end

@implementation OWSDisappearingMessagesJob

- (instancetype)initWithStorageManager:(TSStorageManager *)storageManager
{
    self = [super init];
    if (!self) {
        return self;
    }

    _scheduledAt = ULLONG_MAX;
    _disappearingMessagesFinder = [[OWSDisappearingMessagesFinder alloc] initWithStorageManager:storageManager];

    return self;
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

        DDLogDebug(@"%@ removing message which expired at: %lld", self.tag, message.expiresAt);
        [message remove];
        expirationCount++;
    }];

    DDLogDebug(@"%@ removed %u expired messages", self.tag, expirationCount);
}

- (void)runLoop
{
    // allow next runAt to schedule.
    self.scheduledAt = ULLONG_MAX;

    [self run];

    uint64_t now = [NSDate ows_millisecondTimeStamp];
    NSNumber *nextExpirationTimestampNumber = [self.disappearingMessagesFinder nextExpirationTimestamp];
    if (!nextExpirationTimestampNumber) {
        // In theory we could kill the loop here. It should resume when the next expiring message is saved,
        // But this is a safeguard for any race conditions that exist while running the job as a new message is saved.
        unsigned int delaySeconds = (10 * 60); // 10 minutes.
        DDLogDebug(
            @"%@ No more expiring messages. Setting next check %u seconds into the future", self.tag, delaySeconds);
        [self runBy:now + delaySeconds * 1000];
        return;
    }

    uint64_t nextExpirationAt = [nextExpirationTimestampNumber unsignedLongLongValue];
    uint64_t runByMilliseconds;
    if (nextExpirationAt < now + 1000) {
        DDLogWarn(@"%@ Next run requested at %llu, which is too soon. Delaying by 1 sec to prevent churn",
            self.tag,
            nextExpirationAt);
        runByMilliseconds = now + 1000;
    } else {
        runByMilliseconds = nextExpirationAt;
    }

    DDLogVerbose(@"%@ Requesting next expiration to run by: %llu", self.tag, nextExpirationAt);
    [self runBy:runByMilliseconds];
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
    [self runBy:message.expiresAt];
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

- (void)runBy:(uint64_t)timestamp
{
    // Prevent amplification.
    if (timestamp >= self.scheduledAt) {
        DDLogVerbose(@"%@ expiration already scheduled before %llu", self.tag, timestamp);
        return;
    }

    // Update Schedule
    DDLogVerbose(@"%@ Scheduled expiration run at %llu", self.tag, timestamp);
    self.scheduledAt = timestamp;
    uint64_t millisecondsDelay = timestamp - [NSDate ows_millisecondTimeStamp];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_MSEC * millisecondsDelay),
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
        ^{
            [self runLoop];
        });
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
