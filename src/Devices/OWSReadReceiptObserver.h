//  Copyright © 2016 Open Whisper Systems. All rights reserved.

NS_ASSUME_NONNULL_BEGIN

@class TSMessagesManager;

@interface OWSReadReceiptObserver : NSObject

- (instancetype)initWithMessagesManager:(TSMessagesManager *)messagesManager;
- (void)startObserving;

@end

NS_ASSUME_NONNULL_END