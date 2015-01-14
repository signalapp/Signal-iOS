//
//  MessagesViewController.h
//  Signal
//
//  Created by Dylan Bourgeois on 28/10/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "JSQMessagesViewController.h"
#import "JSQMessages.h"
#import "TSGroupModel.h"
#import <MediaPlayer/MediaPlayer.h>

@class TSThread;

@interface MessagesViewController : JSQMessagesViewController   <UIImagePickerControllerDelegate,
                                                                UINavigationControllerDelegate,
                                                                UITextViewDelegate>


@property (nonatomic,strong) MPMoviePlayerController* player;
- (void)setupWithThread:(TSThread*)thread;
- (void)setupWithTSIdentifier:(NSString*)identifier;
- (void)setupWithTSGroup:(TSGroupModel*)model;

@end
