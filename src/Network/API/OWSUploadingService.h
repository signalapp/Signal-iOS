//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class TSOutgoingMessage;
@class TSNetworkManager;
@class TSAttachmentStream;

extern NSString *const kAttachmentUploadProgressNotification;
extern NSString *const kAttachmentUploadProgressKey;
extern NSString *const kAttachmentUploadAttachmentIDKey;

@interface OWSUploadingService : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithNetworkManager:(TSNetworkManager *)networkManager NS_DESIGNATED_INITIALIZER;

- (void)uploadAttachmentStream:(TSAttachmentStream *)attachmentStream
                       message:(TSOutgoingMessage *)outgoingMessage
                       success:(void (^)())successHandler
                       failure:(void (^)(NSError *error))failureHandler;

@end

NS_ASSUME_NONNULL_END
