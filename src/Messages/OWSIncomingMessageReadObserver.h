//  Created by Michael Kirk on 9/24/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

NS_ASSUME_NONNULL_BEGIN

@class TSStorageManager;
@class TSMessagesManager;

@interface OWSIncomingMessageReadObserver : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithStorageManager:(TSStorageManager *)storageManager
                       messagesManager:(TSMessagesManager *)messagesManager NS_DESIGNATED_INITIALIZER;

- (void)startObserving;

@end

NS_ASSUME_NONNULL_END
