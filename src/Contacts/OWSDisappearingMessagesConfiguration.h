//  Created by Michael Kirk on 9/23/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "TSYapDatabaseObject.h"

NS_ASSUME_NONNULL_BEGIN

extern const uint32_t OWSDisappearingMessagesConfigurationDefaultExpirationDuration;

@interface OWSDisappearingMessagesConfiguration : TSYapDatabaseObject

- (instancetype)initDefaultWithThreadId:(NSString *)threadId;

- (instancetype)initWithThreadId:(NSString *)threadId enabled:(BOOL)isEnabled durationSeconds:(uint32_t)seconds;

@property (nonatomic, getter=isEnabled) BOOL enabled;
@property (nonatomic) uint32_t durationSeconds;
@property (nonatomic, readonly) NSUInteger durationIndex;
@property (nonatomic, readonly) NSString *durationString;
@property (nonatomic, readonly) BOOL dictionaryValueDidChange;
@property (readonly, getter=isNewRecord) BOOL newRecord;

+ (instancetype)fetchOrCreateDefaultWithThreadId:(NSString *)threadId;

+ (NSArray<NSNumber *> *)validDurationsSeconds;

+ (NSString *)stringForDurationSeconds:(uint32_t)durationSeconds;

@end

NS_ASSUME_NONNULL_END
