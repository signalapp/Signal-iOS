//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@class TSVideoAttachmentAdapter;
@class YapDatabaseConnection;

@protocol OWSAudioAttachmentPlayerDelegate <NSObject>

- (BOOL)isAudioPlaying;
- (void)setIsAudioPlaying:(BOOL)isAudioPlaying;

- (BOOL)isPaused;
- (void)setIsPaused:(BOOL)isPaused;

- (void)setAudioProgress:(CGFloat)progress duration:(CGFloat)duration;
- (void)setAudioIconToPlay;
- (void)setAudioIconToPause;

@end

#pragma mark -

@interface OWSAudioAttachmentPlayer : NSObject <AVAudioPlayerDelegate>

@property (nonatomic, readonly, weak) id<OWSAudioAttachmentPlayerDelegate> delegate;

// This property can be used to associate instances of the player with view
// or model objects.
@property (nonatomic, weak) id owner;

// A convenience initializer for MessagesViewController.
//
// It assumes the delegate (e.g. view) for this player will be the adapter.
- (instancetype)initWithMediaAdapter:(TSVideoAttachmentAdapter *)mediaAdapter
                  databaseConnection:(YapDatabaseConnection *)databaseConnection;

// An generic initializer.
- (instancetype)initWithMediaUrl:(NSURL *)mediaUrl delegate:(id<OWSAudioAttachmentPlayerDelegate>)delegate;

- (void)play;
- (void)pause;
- (void)stop;
- (void)togglePlayState;

@end

NS_ASSUME_NONNULL_END
