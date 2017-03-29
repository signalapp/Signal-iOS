//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageEditing.h"
#import <JSQMessagesViewController/JSQVideoMediaItem.h>

NS_ASSUME_NONNULL_BEGIN

@class TSAttachmentStream;

@interface TSVideoAttachmentAdapter : JSQVideoMediaItem <OWSMessageEditing>

@property NSString *attachmentId;
@property (nonatomic, strong) NSString *contentType;
@property (nonatomic) BOOL isAudioPlaying;
@property (nonatomic) BOOL isPaused;

- (instancetype)initWithAttachment:(TSAttachmentStream *)attachment incoming:(BOOL)incoming;

- (BOOL)isAudio;
- (BOOL)isVideo;
- (void)setAudioProgressFromFloat:(float)progress;
- (void)setAudioIconToPlay;
- (void)setAudioIconToPause;
- (void)setDurationOfAudio:(NSTimeInterval)duration;
- (void)resetAudioDuration;

@end

NS_ASSUME_NONNULL_END
