//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSAttachment.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * A TSAttachmentPointer is a yet-to-be-downloaded attachment.
 */
@interface TSAttachmentPointer : TSAttachment

- (instancetype)initWithServerId:(UInt64)serverId
                             key:(NSData *)key
                          digest:(NSData *)digest
                     contentType:(NSString *)contentType
                           relay:(NSString *)relay NS_DESIGNATED_INITIALIZER;

@property (nonatomic, readonly) NSString *relay;
@property (atomic, readwrite, getter=isDownloading) BOOL downloading;
@property (atomic, readwrite, getter=hasFailed) BOOL failed;

// Though now required, `digest` may be null for pre-existing records or from
// messages received from other clients
@property (nullable, nonatomic, readonly) NSData *digest;

@end

NS_ASSUME_NONNULL_END
