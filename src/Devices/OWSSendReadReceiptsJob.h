//  Created by Michael Kirk on 9/24/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

NS_ASSUME_NONNULL_BEGIN

@class TSMessagesManager;
@class TSIncomingMessage;

@interface OWSSendReadReceiptsJob : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithMessagesManager:(TSMessagesManager *)messagesManager NS_DESIGNATED_INITIALIZER;
- (void)runWith:(TSIncomingMessage *)message;


@end

NS_ASSUME_NONNULL_END
