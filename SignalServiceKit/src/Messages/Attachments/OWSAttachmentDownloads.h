//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class SDSAnyReadTransaction;
@class TSAttachment;
@class TSAttachmentPointer;
@class TSAttachmentStream;
@class TSMessage;

typedef void (^AttachmentDownloadSuccess)(TSAttachmentStream *attachmentStream);
typedef void (^AttachmentDownloadFailure)(NSError *error);

@interface OWSAttachmentDownloadJob : NSObject

@property (nonatomic, readonly) NSString *attachmentId;
@property (nonatomic, readonly, nullable) TSMessage *message;
@property (nonatomic, readonly) AttachmentDownloadSuccess success;
@property (nonatomic, readonly) AttachmentDownloadFailure failure;
@property (atomic) CGFloat progress;

@end

#pragma mark -

// TODO: We might want to pull out a protocol, convert this to an impl
//       and use a mock in our tests.
/**
 * Given incoming attachment protos, determines which we support.
 * It can download those that we support and notifies threads when it receives unsupported attachments.
 */
@interface OWSAttachmentDownloads : NSObject

- (nullable NSNumber *)downloadProgressForAttachmentId:(NSString *)attachmentId;

- (void)downloadAttachmentsForMessage:(TSMessage *)message
          bypassPendingMessageRequest:(BOOL)bypassPendingMessageRequest
                          attachments:(NSArray<TSAttachment *> *)attachments
                              success:(void (^)(NSArray<TSAttachmentStream *> *attachmentStreams))success
                              failure:(void (^)(NSError *error))failure;

// This will try to download a single attachment.
//
// success/failure are always called on a worker queue.
- (void)downloadAttachmentPointer:(TSAttachmentPointer *)attachmentPointer
                          message:(TSMessage *)message
      bypassPendingMessageRequest:(BOOL)bypassPendingMessageRequest
                          success:(void (^)(NSArray<TSAttachmentStream *> *attachmentStreams))success
                          failure:(void (^)(NSError *error))failure;

// This will try to download a single attachment.
//
// success/failure are always called on a worker queue.
- (void)downloadAttachmentPointer:(TSAttachmentPointer *)attachmentPointer
      bypassPendingMessageRequest:(BOOL)bypassPendingMessageRequest
                          success:(void (^)(NSArray<TSAttachmentStream *> *attachmentStreams))success
                          failure:(void (^)(NSError *error))failure;

- (void)enqueueJobForAttachmentId:(NSString *)attachmentId
                          message:(nullable TSMessage *)message
                          success:(void (^)(TSAttachmentStream *attachmentStream))success
                          failure:(void (^)(NSError *error))failure;

@end

NS_ASSUME_NONNULL_END
