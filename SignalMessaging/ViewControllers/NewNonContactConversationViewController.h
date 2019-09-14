//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "SelectRecipientViewController.h"

@class SignalServiceAddress;

@protocol NewNonContactConversationViewControllerDelegate <NSObject>

- (void)recipientAddressWasSelected:(SignalServiceAddress *)address;

@end

#pragma mark -

@interface NewNonContactConversationViewController : SelectRecipientViewController

@property (nonatomic, weak) id<NewNonContactConversationViewControllerDelegate> nonContactConversationDelegate;

@end
