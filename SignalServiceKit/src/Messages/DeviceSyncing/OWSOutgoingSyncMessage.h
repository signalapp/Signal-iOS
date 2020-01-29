//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "TSOutgoingMessage.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Abstract base class used for the family of sync messages which take care
 * of keeping your multiple registered devices consistent. E.g. sharing contacts, sharing groups,
 * notifiying your devices of sent messages, and "read" receipts.
 */
@interface OWSOutgoingSyncMessage : TSOutgoingMessage

- (instancetype)initOutgoingMessageWithBuilder:(TSOutgoingMessageBuilder *)outgoingMessageBuilder NS_UNAVAILABLE;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithThread:(TSThread *)thread NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithTimestamp:(uint64_t)timestamp thread:(TSThread *)thread NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
