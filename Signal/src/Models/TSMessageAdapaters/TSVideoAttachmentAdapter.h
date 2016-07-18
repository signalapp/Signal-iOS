//  Created by Frederic Jacobs on 17/12/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.

#import "OWSMessageEditing.h"
#import <JSQMessagesViewController/JSQVideoMediaItem.h>

@class TSAttachmentStream;

@interface TSVideoAttachmentAdapter : JSQVideoMediaItem <OWSMessageEditing>

@property NSString *attachmentId;
@property (nonatomic, strong) NSString *contentType;
@property (nonatomic) BOOL isAudioPlaying;
@property (nonatomic) BOOL isPaused;

- (instancetype)initWithAttachment:(TSAttachmentStream *)attachment incoming:(BOOL)incoming;

- (BOOL)isImage;
- (BOOL)isAudio;
- (BOOL)isVideo;
- (void)setAudioProgressFromFloat:(float)progress;
- (void)setAudioIconToPlay;
- (void)setAudioIconToPause;
- (void)setDurationOfAudio:(NSTimeInterval)duration;
- (void)resetAudioDuration;

@end
