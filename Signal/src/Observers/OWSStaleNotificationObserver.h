//
//  OWSStaleNotificationObserver.h
//  Signal
//
//  Created by Michael Kirk on 9/14/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class PushManager;

@interface OWSStaleNotificationObserver : NSObject

- (instancetype)initWithPushManager:(PushManager *)pushManager NS_DESIGNATED_INITIALIZER;
- (void)startObserving;

@end

NS_ASSUME_NONNULL_END
