//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageSender.h"

NS_ASSUME_NONNULL_BEGIN

@class TSAttachmentStream;
@class TSNetworkManager;
@class TSOutgoingMessage;

extern NSString *const kAttachmentUploadProgressNotification;
extern NSString *const kAttachmentUploadProgressKey;
extern NSString *const kAttachmentUploadAttachmentIDKey;

@interface OWSUploadingService : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithNetworkManager:(TSNetworkManager *)networkManager NS_DESIGNATED_INITIALIZER;

- (void)uploadAttachmentStream:(TSAttachmentStream *)attachmentStream
                       message:(TSOutgoingMessage *)outgoingMessage
                       success:(void (^)(void))successHandler
                       failure:(RetryableFailureHandler)failureHandler;

@end

NS_ASSUME_NONNULL_END
