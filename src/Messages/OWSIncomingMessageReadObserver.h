//  Created by Michael Kirk on 9/24/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

NS_ASSUME_NONNULL_BEGIN

@class TSStorageManager;
@class OWSMessageSender;

@interface OWSIncomingMessageReadObserver : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithStorageManager:(TSStorageManager *)storageManager
                         messageSender:(OWSMessageSender *)messageSender NS_DESIGNATED_INITIALIZER;

- (void)startObserving;

@end

NS_ASSUME_NONNULL_END
