//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSDisappearingMessagesConfiguration.h"
#import "NSDate+OWS.h"
#import "NSString+SSK.h"

NS_ASSUME_NONNULL_BEGIN

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

- (nullable instancetype)initWithCoder:(NSCoder *)coder
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
                                     transaction:(YapDatabaseReadTransaction *)transaction
{
    OWSDisappearingMessagesConfiguration *savedConfiguration =
        [self fetchObjectWithUniqueID:threadId transaction:transaction];
    if (savedConfiguration) {
        return savedConfiguration;
    } else {
        return [[self alloc] initDefaultWithThreadId:threadId];
    }
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
    return [NSString formatDurationSeconds:self.durationSeconds useShortFormat:NO];
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
