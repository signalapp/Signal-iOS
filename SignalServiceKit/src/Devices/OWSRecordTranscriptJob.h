//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSIncomingSentMessageTranscript;
@class TSAttachmentStream;
@class YapDatabaseReadWriteTransaction;

// This job is used to process "outgoing message" notifications from linked devices.
@interface OWSRecordTranscriptJob : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithIncomingSentMessageTranscript:(OWSIncomingSentMessageTranscript *)incomingSentMessageTranscript
    NS_DESIGNATED_INITIALIZER;

- (void)runWithAttachmentHandler:(void (^)(NSArray<TSAttachmentStream *> *attachmentStreams))attachmentHandler
                     transaction:(YapDatabaseReadWriteTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
