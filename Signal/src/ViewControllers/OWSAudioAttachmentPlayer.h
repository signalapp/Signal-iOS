//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class TSVideoAttachmentAdapter;

typedef NS_ENUM(NSInteger, AudioPlaybackState) {
    AudioPlaybackState_Stopped,
    AudioPlaybackState_Playing,
    AudioPlaybackState_Paused,
};

@protocol OWSAudioAttachmentPlayerDelegate <NSObject>

- (AudioPlaybackState)audioPlaybackState;
- (void)setAudioPlaybackState:(AudioPlaybackState)state;

- (void)setAudioProgress:(CGFloat)progress duration:(CGFloat)duration;

@end

#pragma mark -

@interface OWSAudioAttachmentPlayer : NSObject

@property (nonatomic, readonly, weak) id<OWSAudioAttachmentPlayerDelegate> delegate;

// This property can be used to associate instances of the player with view
// or model objects.
@property (nonatomic, weak) id owner;

// An generic initializer.
- (instancetype)initWithMediaUrl:(NSURL *)mediaUrl delegate:(id<OWSAudioAttachmentPlayerDelegate>)delegate;

- (void)play;
- (void)pause;
- (void)stop;
- (void)togglePlayState;

@end

NS_ASSUME_NONNULL_END
