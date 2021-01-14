//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

typedef NS_CLOSED_ENUM(NSInteger, AudioPlaybackState) {
    AudioPlaybackState_Stopped,
    AudioPlaybackState_Playing,
    AudioPlaybackState_Paused,
};

@protocol OWSAudioPlayerDelegate <NSObject>

@property (nonatomic) AudioPlaybackState audioPlaybackState;

- (void)setAudioProgress:(NSTimeInterval)progress duration:(NSTimeInterval)duration;

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

@property (nonatomic, weak) id<OWSAudioPlayerDelegate> delegate;

@property (nonatomic) BOOL isLooping;

- (instancetype)initWithMediaUrl:(NSURL *)mediaUrl audioBehavior:(OWSAudioBehavior)audioBehavior;

- (void)play;
- (void)pause;
- (void)setupAudioPlayer;
- (void)stop;
- (void)togglePlayState;
- (void)setCurrentTime:(NSTimeInterval)currentTime;

@end

NS_ASSUME_NONNULL_END
