//  Created by Michael Kirk on 9/23/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSDisappearingMessagesConfiguration.h"

NS_ASSUME_NONNULL_BEGIN

const uint32_t OWSDisappearingMessagesConfigurationDefaultExpirationDuration = 60 * 60 * 24; // 1 day.

@interface OWSDisappearingMessagesConfiguration ()

// Transient record lifecycle attributes.
@property (atomic) NSDictionary *originalDictionaryValue;
@property (atomic, getter=isNewRecord) BOOL newRecord;

@end

@implementation OWSDisappearingMessagesConfiguration

- (instancetype)initDefaultWithThreadId:(NSString *)threadId
{
    return [self initWithThreadId:threadId
                          enabled:NO
                  durationSeconds:OWSDisappearingMessagesConfigurationDefaultExpirationDuration];
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];

    _originalDictionaryValue = [self dictionaryValue];
    _newRecord = NO;

    return self;
}

- (instancetype)initWithThreadId:(NSString *)threadId enabled:(BOOL)isEnabled durationSeconds:(uint32_t)seconds
{
    self = [super initWithUniqueId:threadId];
    if (!self) {
        return self;
    }

    _enabled = isEnabled;
    _durationSeconds = seconds;
    _originalDictionaryValue = [NSDictionary new];
    _newRecord = YES;

    return self;
}

+ (instancetype)fetchOrCreateDefaultWithThreadId:(NSString *)threadId
{
    OWSDisappearingMessagesConfiguration *savedConfiguration = [self fetchObjectWithUniqueID:threadId];
    if (savedConfiguration) {
        return savedConfiguration;
    } else {
        return [[self alloc] initDefaultWithThreadId:threadId];
    }
}

+ (NSString *)stringForDurationSeconds:(uint32_t)durationSeconds
{
    NSString *amountFormat;
    uint32_t duration;

    uint32_t secondsPerMinute = 60;
    uint32_t secondsPerHour = secondsPerMinute * 60;
    uint32_t secondsPerDay = secondsPerHour * 24;
    uint32_t secondsPerWeek = secondsPerDay * 7;

    if (durationSeconds < secondsPerMinute) { // XX Seconds
        amountFormat = NSLocalizedString(@"SECONDS_TIME_AMOUNT",
            @"{{number of seconds}} embedded in strings, e.g. 'Alice updated disappearing messages "
            @"expiration to {{5 seconds}}'. See other *_TIME_AMOUNT strings");
        duration = durationSeconds;
    } else if (durationSeconds < secondsPerMinute * 1.5) { // 1 Minute
        amountFormat = NSLocalizedString(@"SINGLE_MINUTE_TIME_AMOUNT",
            @"{{1 minute}} embedded in strings, e.g. 'Alice updated disappearing messages "
            @"expiration to {{1 minute}}'. See other *_TIME_AMOUNT strings");
        duration = durationSeconds / secondsPerMinute;
    } else if (durationSeconds < secondsPerHour) { // Multiple Minutes
        amountFormat = NSLocalizedString(@"MINUTES_TIME_AMOUNT",
            @"{{number of minutes}} embedded in strings, e.g. 'Alice updated disappearing messages "
            @"expiration to {{5 minutes}}'. See other *_TIME_AMOUNT strings");

        duration = durationSeconds / secondsPerMinute;
    } else if (durationSeconds < secondsPerHour * 1.5) { // 1 Hour
        amountFormat = NSLocalizedString(@"SINGLE_HOUR_TIME_AMOUNT",
            @"{{1 hour}} embedded in strings, e.g. 'Alice updated disappearing messages "
            @"expiration to {{1 hour}}'. See other *_TIME_AMOUNT strings");

        duration = durationSeconds / secondsPerHour;
    } else if (durationSeconds < secondsPerDay) { // Multiple Hours
        amountFormat = NSLocalizedString(@"HOURS_TIME_AMOUNT",
            @"{{number of hours}} embedded in strings, e.g. 'Alice updated disappearing messages "
            @"expiration to {{5 hours}}'. See other *_TIME_AMOUNT strings");

        duration = durationSeconds / secondsPerHour;
    } else if (durationSeconds < secondsPerDay * 1.5) { // 1 Day
        amountFormat = NSLocalizedString(@"SINGLE_DAY_TIME_AMOUNT",
            @"{{1 day}} embedded in strings, e.g. 'Alice updated disappearing messages "
            @"expiration to {{1 day}}'. See other *_TIME_AMOUNT strings");

        duration = durationSeconds / secondsPerDay;
    } else if (durationSeconds < secondsPerWeek) { // Multiple Days
        amountFormat = NSLocalizedString(@"DAYS_TIME_AMOUNT",
            @"{{number of days}} embedded in strings, e.g. 'Alice updated disappearing messages "
            @"expiration to {{5 days}}'. See other *_TIME_AMOUNT strings");

        duration = durationSeconds / secondsPerDay;
    } else if (durationSeconds < secondsPerWeek * 1.5) { // 1 Week
        amountFormat = NSLocalizedString(@"SINGLE_WEEK_TIME_AMOUNT",
            @"{{1 week}} embedded in strings, e.g. 'Alice updated disappearing messages "
            @"expiration to {{1 week}}'. See other *_TIME_AMOUNT strings");

        duration = durationSeconds / secondsPerWeek;
    } else { // Multiple weeks
        amountFormat = NSLocalizedString(@"WEEKS_TIME_AMOUNT",
            @"{{number of weeks}}, embedded in strings, e.g. 'Alice updated disappearing messages "
            @"expiration to {{5 weeks}}'. See other *_TIME_AMOUNT strings");

        duration = durationSeconds / secondsPerWeek;
    }

    return [NSString stringWithFormat:amountFormat, duration];
}

+ (NSArray<NSNumber *> *)validDurationsSeconds
{
    return @[ @(5),
              @(10),
              @(30),
              @(60),
              @(300),
              @(1800),
              @(3600),
              @(21600),
              @(43200),
              @(86400),
              @(604800) ];
}

- (NSUInteger)durationIndex
{
    return [[self.class validDurationsSeconds] indexOfObject:@(self.durationSeconds)];
}

- (NSString *)durationString
{
    return [self.class stringForDurationSeconds:self.durationSeconds];
}

#pragma mark - Dirty Tracking

+ (MTLPropertyStorage)storageBehaviorForPropertyWithKey:(NSString *)propertyKey
{
    // Don't persist transient properties
    if ([propertyKey isEqualToString:@"originalDictionaryValue"]
        ||[propertyKey isEqualToString:@"newRecord"]) {
        return MTLPropertyStorageNone;
    } else {
        return [super storageBehaviorForPropertyWithKey:propertyKey];
    }
}

- (BOOL)dictionaryValueDidChange
{
    return ![self.originalDictionaryValue isEqual:[self dictionaryValue]];
}

- (void)saveWithTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
    [super saveWithTransaction:transaction];
    self.originalDictionaryValue = [self dictionaryValue];
    self.newRecord = NO;
}

@end

NS_ASSUME_NONNULL_END
