//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <JSQMessagesViewController/JSQMessagesViewController.h>

@class TSThread;

extern NSString *const OWSMessagesViewControllerDidAppearNotification;

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
