//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSIncomingSentMessageTranscript;
@class OWSPrimaryStorage;
@class OWSReadReceiptManager;
@class TSAttachmentStream;
@class TSNetworkManager;
@class YapDatabaseReadWriteTransaction;

@protocol ContactsManagerProtocol;

// This job is used to process "outgoing message" notifications from linked devices.
@interface OWSRecordTranscriptJob : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithIncomingSentMessageTranscript:(OWSIncomingSentMessageTranscript *)incomingSentMessageTranscript;
- (instancetype)initWithIncomingSentMessageTranscript:(OWSIncomingSentMessageTranscript *)incomingSentMessageTranscript
                                       networkManager:(TSNetworkManager *)networkManager
                                       primaryStorage:(OWSPrimaryStorage *)primaryStorage
                                   readReceiptManager:(OWSReadReceiptManager *)readReceiptManager
                                      contactsManager:(id<ContactsManagerProtocol>)contactsManager
    NS_DESIGNATED_INITIALIZER;

- (void)runWithAttachmentHandler:(void (^)(NSArray<TSAttachmentStream *> *attachmentStreams))attachmentHandler
                     transaction:(YapDatabaseReadWriteTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
