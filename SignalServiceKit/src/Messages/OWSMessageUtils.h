//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class TSThread;

@interface OWSMessageUtils : NSObject

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)sharedManager;

- (NSUInteger)unreadMessagesCount;
- (NSUInteger)unreadMessagesCountExcept:(TSThread *)thread;
- (NSUInteger)unreadMessagesInThread:(TSThread *)thread;

- (void)updateApplicationBadgeCount;

@end

NS_ASSUME_NONNULL_END
