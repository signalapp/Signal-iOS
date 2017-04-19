//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageEditing.h"
#import "OWSMessageMediaAdapter.h"
#import <JSQMessagesViewController/JSQPhotoMediaItem.h>

NS_ASSUME_NONNULL_BEGIN

@class TSAttachmentStream;

@interface TSPhotoAdapter : JSQPhotoMediaItem <OWSMessageEditing, OWSMessageMediaAdapter>

- (instancetype)initWithAttachment:(TSAttachmentStream *)attachment incoming:(BOOL)incoming;

@property TSAttachmentStream *attachment;
@property NSString *attachmentId;

@end

NS_ASSUME_NONNULL_END
