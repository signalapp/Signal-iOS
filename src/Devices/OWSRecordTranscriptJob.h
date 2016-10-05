//  Created by Michael Kirk on 9/23/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

NS_ASSUME_NONNULL_BEGIN

@class OWSIncomingSentMessageTranscript;
@class TSMessagesManager;

@interface OWSRecordTranscriptJob : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithMessagesManager:(TSMessagesManager *)messagesManager
          incomingSentMessageTranscript:(OWSIncomingSentMessageTranscript *)incomingSendtMessageTranscript NS_DESIGNATED_INITIALIZER;

- (void)run;

@end

NS_ASSUME_NONNULL_END
