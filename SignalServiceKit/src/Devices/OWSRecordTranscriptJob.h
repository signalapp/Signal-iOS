//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSIncomingSentMessageTranscript;
@class SDSAnyWriteTransaction;
@class SSKProtoSyncMessageSentUpdate;
@class TSAttachmentStream;

// This job is used to process "outgoing message" notifications from linked devices.
@interface OWSRecordTranscriptJob : NSObject

- (instancetype)init NS_UNAVAILABLE;

+ (void)processIncomingSentMessageTranscript:(OWSIncomingSentMessageTranscript *)incomingSentMessageTranscript
                           attachmentHandler:(void (^)(
                                                 NSArray<TSAttachmentStream *> *attachmentStreams))attachmentHandler
                                 transaction:(SDSAnyWriteTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
