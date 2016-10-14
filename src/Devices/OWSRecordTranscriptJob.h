//  Created by Michael Kirk on 9/23/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

NS_ASSUME_NONNULL_BEGIN

@class OWSIncomingSentMessageTranscript;
@class OWSMessageSender;
@class TSNetworkManager;
@class TSAttachmentStream;

@interface OWSRecordTranscriptJob : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithIncomingSentMessageTranscript:(OWSIncomingSentMessageTranscript *)incomingSentMessageTranscript
                                        messageSender:(OWSMessageSender *)messageSender
                                       networkManager:(TSNetworkManager *)networkManager NS_DESIGNATED_INITIALIZER;

- (void)runWithAttachmentHandler:(void (^)(TSAttachmentStream *attachmentStream))attachmentHandler;

@end

NS_ASSUME_NONNULL_END
