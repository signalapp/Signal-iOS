//
//  MessagesViewController.h
//  Signal
//
//  Created by Dylan Bourgeois on 28/10/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "JSQMessagesViewController.h"
#import "JSQMessages.h"

@class TSThread;

@interface MessagesViewController : JSQMessagesViewController <UIImagePickerControllerDelegate,UINavigationControllerDelegate>

- (void)setupWithThread:(TSThread*)thread;
- (void)setupWithTSIdentifier:(NSString*)identifier;

@end
