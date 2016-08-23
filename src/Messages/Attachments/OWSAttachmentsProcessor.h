//  Copyright © 2016 Open Whisper Systems. All rights reserved.

NS_ASSUME_NONNULL_BEGIN

@class TSThread;
@class TSMessagesManager;
@class OWSSignalServiceProtosAttachmentPointer;

/**
 * Given incoming attachment protos, determines which we support.
 * It can download those that we support and notifies threads when it receives unsupported attachments.
 */
@interface OWSAttachmentsProcessor : NSObject

@property (nonatomic, readonly) NSArray<NSString *> *attachmentIds;
@property (nonatomic, readonly) NSArray<NSString *> *supportedAttachmentIds;
@property (nonatomic, readonly) BOOL hasSupportedAttachments;

- (instancetype)initWithAttachmentPointersProtos:(NSArray<OWSSignalServiceProtosAttachmentPointer *> *)attachmentProtos
                                       timestamp:(uint64_t)timestamp
                                           relay:(nullable NSString *)relay
                                   avatarGroupId:(nullable NSData *)avatarGroupId
                                        inThread:(TSThread *)thread
                                 messagesManager:(TSMessagesManager *)messagesManager;

- (void)fetchAttachmentsForMessageId:(nullable NSString *)messageId;

@end

NS_ASSUME_NONNULL_END
