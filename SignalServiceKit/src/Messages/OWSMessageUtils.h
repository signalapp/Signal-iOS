//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class TSThread;

@interface OWSMessageUtils : NSObject
+ (NSUInteger)unreadMessagesCount;
+ (NSUInteger)unreadMessagesCountExcept:(TSThread *)thread;
@end

NS_ASSUME_NONNULL_END
