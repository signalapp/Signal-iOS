//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

extern NSString *const kAttachmentDownloadProgressNotification;
extern NSString *const kAttachmentDownloadProgressKey;
extern NSString *const kAttachmentDownloadAttachmentIDKey;

@class OWSPrimaryStorage;
@class SSKProtoAttachmentPointer;
@class TSAttachmentPointer;
@class TSAttachmentStream;
@class TSMessage;
@class TSNetworkManager;
@class TSThread;
@class YapDatabaseReadWriteTransaction;

/**
 * Given incoming attachment protos, determines which we support.
 * It can download those that we support and notifies threads when it receives unsupported attachments.
 */
@interface OWSAttachmentsProcessor : NSObject

@property (nonatomic, readonly) NSArray<TSAttachmentPointer *> *attachmentPointers;

- (instancetype)init NS_UNAVAILABLE;

/*
 * Retry fetching failed attachment download
 */
- (instancetype)initWithAttachmentPointers:(NSArray<TSAttachmentPointer *> *)attachmentPointers
    NS_DESIGNATED_INITIALIZER;

- (void)fetchAttachmentsForMessage:(nullable TSMessage *)message
                       transaction:(YapDatabaseReadWriteTransaction *)transaction
                           success:(void (^)(NSArray<TSAttachmentStream *> *attachmentStreams))successHandler
                           failure:(void (^)(NSError *error))failureHandler;
@end

NS_ASSUME_NONNULL_END
