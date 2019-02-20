//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSIncomingSentMessageTranscript;
@class SSKProtoSyncMessageSentUpdate;
@class TSAttachmentStream;
@class YapDatabaseReadWriteTransaction;

// This job is used to process "outgoing message" notifications from linked devices.
@interface OWSRecordTranscriptJob : NSObject

- (instancetype)init NS_UNAVAILABLE;

+ (void)processIncomingSentMessageTranscript:(OWSIncomingSentMessageTranscript *)incomingSentMessageTranscript
                           attachmentHandler:(void (^)(
                                                 NSArray<TSAttachmentStream *> *attachmentStreams))attachmentHandler
                                 transaction:(YapDatabaseReadWriteTransaction *)transaction;

+ (void)processSentUpdateTranscript:(SSKProtoSyncMessageSentUpdate *)sentUpdate
                        transaction:(YapDatabaseReadWriteTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
