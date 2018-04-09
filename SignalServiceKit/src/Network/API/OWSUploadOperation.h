//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSOperation.h"

NS_ASSUME_NONNULL_BEGIN

@class TSOutgoingMessage;
@class YapDatabaseConnection;

extern NSString *const kAttachmentUploadProgressNotification;
extern NSString *const kAttachmentUploadProgressKey;
extern NSString *const kAttachmentUploadAttachmentIDKey;

@interface OWSUploadOperation : OWSOperation

@property (nullable, readonly) NSError *lastError;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithAttachmentId:(NSString *)attachmentId
                        dbConnection:(YapDatabaseConnection *)dbConnection NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
