//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

extern NSString *const kAttachmentDownloadProgressNotification;
extern NSString *const kAttachmentDownloadProgressKey;
extern NSString *const kAttachmentDownloadAttachmentIDKey;

@class OWSPrimaryStorage;
@class OWSSignalServiceProtosAttachmentPointer;
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

@property (nullable, nonatomic, readonly) NSArray<NSString *> *attachmentIds;
@property (nonatomic, readonly) NSArray<NSString *> *supportedAttachmentIds;
@property (nonatomic, readonly) NSArray<TSAttachmentPointer *> *supportedAttachmentPointers;
@property (nonatomic, readonly) BOOL hasSupportedAttachments;

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithAttachmentProtos:(NSArray<OWSSignalServiceProtosAttachmentPointer *> *)attachmentProtos
                                   relay:(nullable NSString *)relay
                          networkManager:(TSNetworkManager *)networkManager
                          primaryStorage:(OWSPrimaryStorage *)primaryStorage
                             transaction:(YapDatabaseReadWriteTransaction *)transaction NS_DESIGNATED_INITIALIZER;

/*
 * Retry fetching failed attachment download
 */
- (instancetype)initWithAttachmentPointer:(TSAttachmentPointer *)attachmentPointer
                           networkManager:(TSNetworkManager *)networkManager
                           primaryStorage:(OWSPrimaryStorage *)primaryStorage NS_DESIGNATED_INITIALIZER;

- (void)fetchAttachmentsForMessage:(nullable TSMessage *)message
                    primaryStorage:(OWSPrimaryStorage *)primaryStorage
                           success:(void (^)(TSAttachmentStream *attachmentStream))successHandler
                           failure:(void (^)(NSError *error))failureHandler;
- (void)fetchAttachmentsForMessage:(nullable TSMessage *)message
                       transaction:(YapDatabaseReadWriteTransaction *)transaction
                           success:(void (^)(TSAttachmentStream *attachmentStream))successHandler
                           failure:(void (^)(NSError *error))failureHandler;
@end

NS_ASSUME_NONNULL_END
