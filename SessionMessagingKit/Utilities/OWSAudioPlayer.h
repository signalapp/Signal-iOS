//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

@class OWSAudioPlayer;

typedef NS_ENUM(NSInteger, AudioPlaybackState) {
    AudioPlaybackState_Stopped,
    AudioPlaybackState_Playing,
    AudioPlaybackState_Paused,
};

@protocol OWSAudioPlayerDelegate

- (AudioPlaybackState)audioPlaybackState;
- (void)setAudioPlaybackState:(AudioPlaybackState)state;
- (void)setAudioProgress:(CGFloat)progress duration:(CGFloat)duration;
- (void)showInvalidAudioFileAlert;
- (void)audioPlayerDidFinishPlaying:(OWSAudioPlayer *)player successfully:(BOOL)flag;

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
// This property can be used to associate instances of the player with view or model objects.
@property (nonatomic, weak) id owner;
@property (nonatomic) BOOL isLooping;
@property (nonatomic) BOOL isPlaying;
@property (nonatomic) float playbackRate;
@property (nonatomic) NSTimeInterval duration;

- (instancetype)initWithMediaUrl:(NSURL *)mediaUrl audioBehavior:(OWSAudioBehavior)audioBehavior;
- (instancetype)initWithMediaUrl:(NSURL *)mediaUrl audioBehavior:(OWSAudioBehavior)audioBehavior delegate:(nullable id<OWSAudioPlayerDelegate>)delegate;
- (void)play;
- (void)setCurrentTime:(NSTimeInterval)currentTime;
- (void)pause;
- (void)stop;
- (void)togglePlayState;

@end

NS_ASSUME_NONNULL_END
