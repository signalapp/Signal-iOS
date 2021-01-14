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

- (void)enqueueJobForAttachmentId:(NSString *)attachmentId
                          message:(nullable TSMessage *)message
                          success:(void (^)(TSAttachmentStream *attachmentStream))success
                          failure:(void (^)(NSError *error))failure;

@end

NS_ASSUME_NONNULL_END
