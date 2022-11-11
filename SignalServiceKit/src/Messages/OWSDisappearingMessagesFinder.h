//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

NS_ASSUME_NONNULL_BEGIN

@class OWSStorage;
@class SDSAnyReadTransaction;
@class TSMessage;
@class TSThread;

@interface OWSDisappearingMessagesFinder : NSObject

- (void)enumerateExpiredMessagesWithBlock:(void (^_Nonnull)(TSMessage *message))block
                              transaction:(SDSAnyReadTransaction *)transaction;

- (NSArray<NSString *> *)fetchAllMessageUniqueIdsWhichFailedToStartExpiringWithTransaction:
    (SDSAnyReadTransaction *)transaction;

/**
 * @return
 *   uint64_t millisecond timestamp wrapped in a number. Retrieve with `unsignedLongLongvalue`.
 *   or nil if there are no upcoming expired messages
 */
- (nullable NSNumber *)nextExpirationTimestampWithTransaction:(SDSAnyReadTransaction *_Nonnull)transaction;

@end

NS_ASSUME_NONNULL_END
