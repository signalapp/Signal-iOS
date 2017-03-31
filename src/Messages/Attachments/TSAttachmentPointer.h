//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSAttachment.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, TSAttachmentPointerState) {
    TSAttachmentPointerStateEnqueued = 0,
    TSAttachmentPointerStateDownloading = 1,
    TSAttachmentPointerStateFailed = 2,
};

/**
 * A TSAttachmentPointer is a yet-to-be-downloaded attachment.
 */
@interface TSAttachmentPointer : TSAttachment

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithServerId:(UInt64)serverId
                             key:(NSData *)key
                          digest:(nullable NSData *)digest
                     contentType:(NSString *)contentType
                           relay:(NSString *)relay;

@property (nonatomic, readonly) NSString *relay;
@property (atomic) TSAttachmentPointerState state;

// Though now required, `digest` may be null for pre-existing records or from
// messages received from other clients
@property (nullable, nonatomic, readonly) NSData *digest;

@end

NS_ASSUME_NONNULL_END
