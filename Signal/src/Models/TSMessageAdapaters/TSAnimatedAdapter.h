//
//  TSAnimatedAdapter.h
//  Signal
//
//  Created by Mike Okner (@mikeokner) on 2015-09-01.
//  Copyright (c) 2015 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageEditing.h"
#import <JSQMessagesViewController/JSQPhotoMediaItem.h>

@class TSAttachmentStream;

@interface TSAnimatedAdapter : JSQMediaItem <OWSMessageEditing>

- (instancetype)initWithAttachment:(TSAttachmentStream *)attachment;

- (BOOL)isImage;
- (BOOL)isAudio;
- (BOOL)isVideo;

@property NSString *attachmentId;
@property NSData *fileData;

@end
