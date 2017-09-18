//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class YapDatabase;
@class YapDatabaseReadTransaction;

@interface OWSIncomingMessageFinder : NSObject

- (instancetype)initWithDatabase:(YapDatabase *)database NS_DESIGNATED_INITIALIZER;

/**
 * Must be called before using this finder.
 */
- (void)asyncRegisterExtension;

/**
 * Detects existance of a duplicate incoming message.
 */
- (BOOL)existsMessageWithTimestamp:(uint64_t)timestamp
                          sourceId:(NSString *)sourceId
                    sourceDeviceId:(uint32_t)sourceDeviceId
                       transaction:(YapDatabaseReadTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
