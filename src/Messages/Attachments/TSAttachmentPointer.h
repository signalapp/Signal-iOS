//  Created by Frederic Jacobs on 17/12/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.

#import "TSAttachment.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * A TSAttachmentPointer is a yet-to-be-downloaded attachment.
 */
@interface TSAttachmentPointer : TSAttachment

- (instancetype)initWithServerId:(UInt64)serverId
                             key:(NSData *)key
                     contentType:(NSString *)contentType
                           relay:(NSString *)relay NS_DESIGNATED_INITIALIZER;

@property (nonatomic, readonly) NSString *relay;
@property (atomic, readwrite, getter=isDownloading) BOOL downloading;
@property (atomic, readwrite, getter=hasFailed) BOOL failed;

@end

NS_ASSUME_NONNULL_END
