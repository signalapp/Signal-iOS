//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageEditing.h"
#import <JSQMessagesViewController/JSQPhotoMediaItem.h>

@class TSAttachmentStream;

@interface TSPhotoAdapter : JSQPhotoMediaItem <OWSMessageEditing>

- (instancetype)initWithAttachment:(TSAttachmentStream *)attachment incoming:(BOOL)incoming;

- (BOOL)isImage;
- (BOOL)isAudio;
- (BOOL)isVideo;

@property TSAttachmentStream *attachment;
@property NSString *attachmentId;

@end
