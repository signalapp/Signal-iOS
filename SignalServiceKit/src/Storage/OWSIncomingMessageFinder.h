//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSStorage;
@class SignalServiceAddress;
@class YapDatabaseReadTransaction;

@interface OWSIncomingMessageFinder : NSObject

+ (void)asyncRegisterExtensionWithPrimaryStorage:(OWSStorage *)storage;

/**
 * Detects existance of a duplicate incoming message.
 */
- (BOOL)existsMessageWithTimestamp:(uint64_t)timestamp
                           address:(SignalServiceAddress *)address
                    sourceDeviceId:(uint32_t)sourceDeviceId
                       transaction:(YapDatabaseReadTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
