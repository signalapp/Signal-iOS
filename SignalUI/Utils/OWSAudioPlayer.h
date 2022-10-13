//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

NS_ASSUME_NONNULL_BEGIN

typedef NS_CLOSED_ENUM(NSInteger, AudioPlaybackState) {
    AudioPlaybackState_Stopped,
    AudioPlaybackState_Playing,
    AudioPlaybackState_Paused,
};

@protocol OWSAudioPlayerDelegate <NSObject>

@property (nonatomic) AudioPlaybackState audioPlaybackState;

- (void)setAudioProgress:(NSTimeInterval)progress duration:(NSTimeInterval)duration playbackRate:(float)playbackRate;

@optional
- (void)audioPlayerDidFinish;

@end

#pragma mark -

typedef NS_ENUM(NSUInteger, OWSAudioBehavior) {
    OWSAudioBehavior_Unknown,
    OWSAudioBehavior_Playback,
    OWSAudioBehavior_PlaybackMixWithOthers,
    OWSAudioBehavior_AudioMessagePlayback,
    OWSAudioBehavior_PlayAndRecord,
    OWSAudioBehavior_Call,
};

@interface OWSAudioPlayer : NSObject

@property (nonatomic, nullable, weak) id<OWSAudioPlayerDelegate> delegate;

@property (nonatomic) BOOL isLooping;
@property (nonatomic, readonly) NSTimeInterval duration;
/// 1 (default) is normal playback speed. 0.5 is half speed, 2.0 is twice as fast.
@property (nonatomic) float playbackRate;

- (instancetype)initWithMediaUrl:(NSURL *)mediaUrl audioBehavior:(OWSAudioBehavior)audioBehavior;

- (void)play;
- (void)pause;
- (void)setupAudioPlayer;
- (void)stop;
- (void)togglePlayState;
- (void)setCurrentTime:(NSTimeInterval)currentTime;

@end

NS_ASSUME_NONNULL_END
