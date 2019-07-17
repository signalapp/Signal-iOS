//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

extern NSString *const kAttachmentDownloadProgressNotification;
extern NSString *const kAttachmentDownloadProgressKey;
extern NSString *const kAttachmentDownloadAttachmentIDKey;

@class SDSAnyReadTransaction;
@class SSKProtoAttachmentPointer;
@class TSAttachment;
@class TSAttachmentPointer;
@class TSAttachmentStream;
@class TSMessage;

#pragma mark -

// TODO: We might want to pull out a protocol, convert this to an impl
//       and use a mock in our tests.
/**
 * Given incoming attachment protos, determines which we support.
 * It can download those that we support and notifies threads when it receives unsupported attachments.
 */
@interface OWSAttachmentDownloads : NSObject

- (nullable NSNumber *)downloadProgressForAttachmentId:(NSString *)attachmentId;

// This will try to download all un-downloaded _body_ attachments for a given message.
// Any attachments for the message which are already downloaded are skipped BUT
// they are included in the success callback.
//
// success/failure are always called on a worker queue.
- (void)downloadBodyAttachmentsForMessage:(TSMessage *)message
                              transaction:(SDSAnyReadTransaction *)transaction
                                  success:(void (^)(NSArray<TSAttachmentStream *> *attachmentStreams))success
                                  failure:(void (^)(NSError *error))failure;

// This will try to download all un-downloaded attachments for a given message.
// Any attachments for the message which are already downloaded are skipped BUT
// they are included in the success callback.
//
// success/failure are always called on a worker queue.
- (void)downloadAllAttachmentsForMessage:(TSMessage *)message
                             transaction:(SDSAnyReadTransaction *)transaction
                                 success:(void (^)(NSArray<TSAttachmentStream *> *attachmentStreams))success
                                 failure:(void (^)(NSError *error))failure;

// This will try to download a single attachment.
//
// success/failure are always called on a worker queue.
- (void)downloadAttachmentPointer:(TSAttachmentPointer *)attachmentPointer
                          message:(nullable TSMessage *)message
                          success:(void (^)(NSArray<TSAttachmentStream *> *attachmentStreams))success
                          failure:(void (^)(NSError *error))failure;

@end

NS_ASSUME_NONNULL_END
