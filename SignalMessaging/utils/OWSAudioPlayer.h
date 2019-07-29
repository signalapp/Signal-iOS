//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, AudioPlaybackState) {
    AudioPlaybackState_Stopped,
    AudioPlaybackState_Playing,
    AudioPlaybackState_Paused,
};

@protocol OWSAudioPlayerDelegate <NSObject>

- (AudioPlaybackState)audioPlaybackState;
- (void)setAudioPlaybackState:(AudioPlaybackState)state;

- (void)setAudioProgress:(CGFloat)progress duration:(CGFloat)duration;

@optional
- (void)audioPlayerDidFinish;

@end

#pragma mark -

typedef NS_ENUM(NSUInteger, OWSAudioBehavior) {
    OWSAudioBehavior_Unknown,
    OWSAudioBehavior_Playback,
    OWSAudioBehavior_AudioMessagePlayback,
    OWSAudioBehavior_PlayAndRecord,
    OWSAudioBehavior_Call,
};

@interface OWSAudioPlayer : NSObject

@property (nonatomic, readonly, weak) id<OWSAudioPlayerDelegate> delegate;

// This property can be used to associate instances of the player with view
// or model objects.
@property (nonatomic, weak) id owner;

@property (nonatomic) BOOL isLooping;

- (instancetype)initWithMediaUrl:(NSURL *)mediaUrl audioBehavior:(OWSAudioBehavior)audioBehavior;

- (instancetype)initWithMediaUrl:(NSURL *)mediaUrl
                     audioBehavior:(OWSAudioBehavior)audioBehavior
                        delegate:(id<OWSAudioPlayerDelegate>)delegate;

- (void)play;
- (void)pause;
- (void)setupAudioPlayer;
- (void)stop;
- (void)togglePlayState;
- (void)setCurrentTime:(NSTimeInterval)currentTime;

@end

NS_ASSUME_NONNULL_END
