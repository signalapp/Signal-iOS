//
//  TSAttachementAdapter.h
//  Signal
//
//  Created by Frederic Jacobs on 17/12/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <JSQMessagesViewController/JSQVideoMediaItem.h>
#import "TSAttachmentStream.h"
#import <Foundation/Foundation.h>

@interface TSVideoAttachmentAdapter : JSQVideoMediaItem

@property NSString *attachmentId;
@property (nonatomic,strong) NSString* contentType;
@property (nonatomic) BOOL isAudioPlaying;
@property (nonatomic) BOOL isPaused;
@property (nonatomic) NSTimeInterval audioCurrentTime;

- (instancetype)initWithAttachment:(TSAttachmentStream*)attachment incoming:(BOOL)incoming;

- (BOOL)isImage;
- (BOOL)isAudio;
- (BOOL)isVideo;
- (void)setAudioProgressFromFloat:(float)progress;
- (void)setAudioIconToPlay;
- (void)setAudioIconToPause;
- (void)setDurationOfAudio:(NSTimeInterval)duration;
- (void)resetAudioDuration;

@end
