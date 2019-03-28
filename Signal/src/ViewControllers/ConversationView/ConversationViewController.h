//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import <SignalMessaging/OWSViewController.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, ConversationViewAction) {
    ConversationViewActionNone,
    ConversationViewActionCompose,
    ConversationViewActionAudioCall,
    ConversationViewActionVideoCall,
};

@class TSThread;

@interface ConversationViewController : OWSViewController

@property (nonatomic, readonly) TSThread *thread;

- (void)configureForThread:(TSThread *)thread
                    action:(ConversationViewAction)action
            focusMessageId:(nullable NSString *)focusMessageId;

- (void)popKeyBoard;

- (void)scrollToFirstUnreadMessage:(BOOL)isAnimated;

#pragma mark 3D Touch Methods

- (void)peekSetup;
- (void)popped;

@end

NS_ASSUME_NONNULL_END
