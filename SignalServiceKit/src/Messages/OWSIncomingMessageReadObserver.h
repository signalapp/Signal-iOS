//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class TSStorageManager;
@class OWSMessageSender;

@interface OWSIncomingMessageReadObserver : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithMessageSender:(OWSMessageSender *)messageSender NS_DESIGNATED_INITIALIZER;

- (void)startObserving;

@end

NS_ASSUME_NONNULL_END
