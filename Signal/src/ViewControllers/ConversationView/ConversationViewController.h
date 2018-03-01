//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <SignalMessaging/OWSViewController.h>

NS_ASSUME_NONNULL_BEGIN

@class TSThread;

@interface ConversationViewController : OWSViewController

@property (nonatomic, readonly) TSThread *thread;

- (void)configureForThread:(TSThread *)thread
    keyboardOnViewAppearing:(BOOL)keyboardAppearing
        callOnViewAppearing:(BOOL)callOnViewAppearing;

- (void)popKeyBoard;

#pragma mark 3D Touch Methods

- (void)peekSetup;
- (void)popped;

@end

NS_ASSUME_NONNULL_END
