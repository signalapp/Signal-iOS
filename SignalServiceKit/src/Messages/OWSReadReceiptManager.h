//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class TSIncomingMessage;

@interface OWSReadReceiptManager : NSObject

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)sharedManager;

// This method can be called from any thread.
- (void)enqueueIncomingMessage:(TSIncomingMessage *)message;

@end

NS_ASSUME_NONNULL_END
