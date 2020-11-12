//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "SelectRecipientViewController.h"

NS_ASSUME_NONNULL_BEGIN

@protocol AddToGroupViewControllerDelegate <NSObject>

- (void)recipientIdWasAdded:(NSString *)recipientId;

- (BOOL)isRecipientGroupMember:(NSString *)recipientId;

@end

#pragma mark -

@interface AddToGroupViewController : SelectRecipientViewController

@property (nonatomic, weak) id<AddToGroupViewControllerDelegate> addToGroupDelegate;

@property (nonatomic) BOOL hideContacts;

@end

NS_ASSUME_NONNULL_END
