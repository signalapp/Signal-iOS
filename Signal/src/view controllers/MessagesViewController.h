//
//  MessagesViewController.h
//  Signal
//
//  Created by Dylan Bourgeois on 28/10/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import <JSQMessagesViewController/JSQMessagesViewController.h>
#import "TSGroupModel.h"
@class TSThread;

extern NSString *const OWSMessagesViewControllerDidAppearNotification;

@interface MessagesViewController : JSQMessagesViewController <UIImagePickerControllerDelegate,
                                                               UINavigationControllerDelegate,
                                                               UITextViewDelegate,
                                                               AVAudioRecorderDelegate,
                                                               AVAudioPlayerDelegate,
                                                               UIGestureRecognizerDelegate>


@property (nonatomic, readonly) TSThread *thread;
@property (nonatomic, strong) MPMoviePlayerController *videoPlayer;
@property (nonatomic, strong) AVAudioPlayer *audioPlayer;
@property (nonatomic, strong) AVAudioRecorder *audioRecorder;

- (void)configureForThread:(TSThread *)thread keyboardOnViewAppearing:(BOOL)keyboardAppearing;
- (void)popKeyBoard;

#pragma mark 3D Touch Methods

- (void)peekSetup;
- (void)popped;

@end
