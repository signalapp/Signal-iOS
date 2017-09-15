//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class TSIncomingMessage;

// There are three kinds of read receipts:
//
// * Read receipts that this client sends to linked
//   devices to inform them that an message has been read.
// * Read receipts that this client receives from linked
//   devices thet inform this client that an message has been read.
// * Read receipts that this client sends to other users
//   to inform them that an incoming message has been read.
@interface OWSReadReceiptManager : NSObject

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)sharedManager;

// This method can be called from any thread.
- (void)messageWasReadLocally:(TSIncomingMessage *)message;

@end

NS_ASSUME_NONNULL_END
