//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSPrimaryStorage;
@class OWSStorage;
@class YapDatabaseReadTransaction;

@interface OWSIncomingMessageFinder : NSObject

- (instancetype)initWithPrimaryStorage:(OWSPrimaryStorage *)primaryStorage NS_DESIGNATED_INITIALIZER;

+ (NSString *)databaseExtensionName;
+ (void)asyncRegisterExtensionWithPrimaryStorage:(OWSStorage *)storage;

/**
 * Detects existance of a duplicate incoming message.
 */
- (BOOL)existsMessageWithTimestamp:(uint64_t)timestamp
                          sourceId:(NSString *)sourceId
                    sourceDeviceId:(uint32_t)sourceDeviceId
                       transaction:(YapDatabaseReadTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
