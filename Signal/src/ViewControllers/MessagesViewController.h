//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import <JSQMessagesViewController/JSQMessagesViewController.h>
#import "TSGroupModel.h"

@class TSThread;

extern NSString *const OWSMessagesViewControllerDidAppearNotification;

@interface OWSMessagesComposerTextView : JSQMessagesComposerTextView

@end

#pragma mark -

@interface OWSMessagesToolbarContentView : JSQMessagesToolbarContentView

@end

#pragma mark -

@interface OWSMessagesInputToolbar : JSQMessagesInputToolbar

@end

#pragma mark -

@interface MessagesViewController : JSQMessagesViewController

@property (nonatomic, readonly) TSThread *thread;

- (void)configureForThread:(TSThread *)thread
    keyboardOnViewAppearing:(BOOL)keyboardAppearing
        callOnViewAppearing:(BOOL)callOnViewAppearing;

- (void)popKeyBoard;

#pragma mark 3D Touch Methods

- (void)peekSetup;
- (void)popped;

@end
