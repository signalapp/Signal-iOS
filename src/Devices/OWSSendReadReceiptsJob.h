//  Created by Michael Kirk on 9/24/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

NS_ASSUME_NONNULL_BEGIN

@class OWSMessageSender;
@class TSIncomingMessage;

@interface OWSSendReadReceiptsJob : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithMessageSender:(OWSMessageSender *)messageSender NS_DESIGNATED_INITIALIZER;
- (void)runWith:(TSIncomingMessage *)message;


@end

NS_ASSUME_NONNULL_END
