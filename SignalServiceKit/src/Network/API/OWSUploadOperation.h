//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSOperation.h"

NS_ASSUME_NONNULL_BEGIN

@class TSAttachmentStream;

extern NSString *const kAttachmentUploadProgressNotification;
extern NSString *const kAttachmentUploadProgressKey;
extern NSString *const kAttachmentUploadAttachmentIDKey;

@interface OWSUploadOperation : OWSOperation

@property (readonly, nonatomic, nullable) TSAttachmentStream *completedUpload;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithAttachmentId:(NSString *)attachmentId NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
