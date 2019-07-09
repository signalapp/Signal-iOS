//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "SelectRecipientViewController.h"

NS_ASSUME_NONNULL_BEGIN

@class SignalServiceAddress;

@protocol AddToGroupViewControllerDelegate <NSObject>

- (void)recipientAddressWasAdded:(SignalServiceAddress *)address;

- (BOOL)isRecipientGroupMember:(SignalServiceAddress *)address;

@end

#pragma mark -

@interface AddToGroupViewController : SelectRecipientViewController

@property (nonatomic, weak) id<AddToGroupViewControllerDelegate> addToGroupDelegate;

@property (nonatomic) BOOL hideContacts;

@end

NS_ASSUME_NONNULL_END
