//  Created by Frederic Jacobs on 17/12/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.

#import "OWSMessageEditing.h"
#import <JSQMessagesViewController/JSQPhotoMediaItem.h>

@class TSAttachmentStream;

@interface TSPhotoAdapter : JSQPhotoMediaItem <OWSMessageEditing>

- (instancetype)initWithAttachment:(TSAttachmentStream *)attachment;

- (BOOL)isImage;
- (BOOL)isAudio;
- (BOOL)isVideo;

@property TSAttachmentStream *attachment;
@property NSString *attachmentId;

@end
