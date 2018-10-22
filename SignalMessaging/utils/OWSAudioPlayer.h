//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
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

@end

#pragma mark -

@interface OWSAudioPlayer : NSObject

@property (nonatomic, readonly, weak) id<OWSAudioPlayerDelegate> delegate;

// This property can be used to associate instances of the player with view
// or model objects.
@property (nonatomic, weak) id owner;

@property (nonatomic) BOOL isLooping;

- (instancetype)initWithMediaUrl:(NSURL *)mediaUrl;

- (instancetype)initWithMediaUrl:(NSURL *)mediaUrl delegate:(id<OWSAudioPlayerDelegate>)delegate;

// respects silent switch
- (void)playWithCurrentAudioCategory;

// will ensure sound is audible, even if silent switch is enabled
- (void)playWithPlaybackAudioCategory;

- (void)pause;
- (void)stop;
- (void)togglePlayStateWithPlaybackAudioCategory;

@end

NS_ASSUME_NONNULL_END
