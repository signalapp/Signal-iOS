//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "SelectRecipientViewController.h"

@protocol AddToGroupViewControllerDelegate <NSObject>

- (void)recipientIdWasAdded:(NSString *)recipientId;

@end

#pragma mark -

@interface AddToGroupViewController : SelectRecipientViewController

@property (nonatomic, weak) id<AddToGroupViewControllerDelegate> addToGroupDelegate;

@property (nonatomic) BOOL hideContacts;

@end
