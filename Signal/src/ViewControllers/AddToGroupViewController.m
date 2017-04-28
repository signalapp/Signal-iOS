//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "AddToGroupViewController.h"
#import "BlockListUIUtils.h"
#import "ContactAccount.h"
#import "ContactsViewHelper.h"
#import "OWSContactsManager.h"

NS_ASSUME_NONNULL_BEGIN

@interface AddToGroupViewController () <SelectRecipientViewControllerDelegate>

@end

#pragma mark -

@implementation AddToGroupViewController

- (void)loadView
{
    self.delegate = self;

    [super loadView];

    self.title = NSLocalizedString(@"ADD_GROUP_MEMBER_VIEW_TITLE", @"Title for the 'add group member' view.");
}

- (NSString *)phoneNumberSectionTitle
{
    return NSLocalizedString(@"ADD_GROUP_MEMBER_VIEW_PHONE_NUMBER_TITLE",
        @"Title for the 'add by phone number' section of the 'add group member' view.");
}

- (NSString *)phoneNumberButtonText
{
    return NSLocalizedString(@"ADD_GROUP_MEMBER_VIEW_BUTTON",
        @"A label for the 'add by phone number' button in the 'add group member' view");
}

- (NSString *)contactsSectionTitle
{
    return NSLocalizedString(
        @"ADD_GROUP_MEMBER_VIEW_CONTACT_TITLE", @"Title for the 'add contact' section of the 'add group member' view.");
}

- (void)phoneNumberWasSelected:(NSString *)phoneNumber
{
    OWSAssert(phoneNumber.length > 0);

    __weak AddToGroupViewController *weakSelf = self;
    ContactsViewHelper *helper = self.contactsViewHelper;
    if ([helper isRecipientIdBlocked:phoneNumber]) {
        [BlockListUIUtils showUnblockPhoneNumberActionSheet:phoneNumber
                                         fromViewController:self
                                            blockingManager:helper.blockingManager
                                            contactsManager:helper.contactsManager
                                            completionBlock:^(BOOL isBlocked) {
                                                if (isBlocked) {
                                                    [weakSelf addToGroup:phoneNumber];
                                                }
                                            }];
    } else {
        [self addToGroup:phoneNumber];
    }
}

- (void)contactAccountWasSelected:(ContactAccount *)contactAccount
{
    OWSAssert(contactAccount);

    __weak AddToGroupViewController *weakSelf = self;
    ContactsViewHelper *helper = self.contactsViewHelper;
    if ([helper isRecipientIdBlocked:contactAccount.recipientId]) {
        [BlockListUIUtils showUnblockContactAccountActionSheet:contactAccount
                                            fromViewController:self
                                               blockingManager:helper.blockingManager
                                               contactsManager:helper.contactsManager
                                               completionBlock:^(BOOL isBlocked) {
                                                   if (isBlocked) {
                                                       [weakSelf addToGroup:contactAccount.recipientId];
                                                   }
                                               }];
    } else {
        [self addToGroup:contactAccount.recipientId];
    }
}

- (void)addToGroup:(NSString *)recipientId
{
    OWSAssert(recipientId.length > 0);

    [self.addToGroupDelegate recipientIdWasAdded:recipientId];
    [self.navigationController popViewControllerAnimated:YES];
}

- (BOOL)shouldHideLocalNumber
{
    return YES;
}

- (BOOL)shouldHideContacts
{
    return self.hideContacts;
}

- (BOOL)shouldValidatePhoneNumbers
{
    return YES;
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end

NS_ASSUME_NONNULL_END
