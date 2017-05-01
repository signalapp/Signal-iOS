//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "AddToBlockListViewController.h"
#import "BlockListUIUtils.h"
#import "ContactsViewHelper.h"
#import "OWSContactsManager.h"
#import "SignalAccount.h"

NS_ASSUME_NONNULL_BEGIN

@interface AddToBlockListViewController () <SelectRecipientViewControllerDelegate>

@end

#pragma mark -

@implementation AddToBlockListViewController

- (void)loadView
{
    self.delegate = self;

    [super loadView];
    
    self.title = NSLocalizedString(@"SETTINGS_ADD_TO_BLOCK_LIST_TITLE", @"Title for the 'add to block list' view.");
}

- (NSString *)phoneNumberSectionTitle
{
    return NSLocalizedString(@"SETTINGS_ADD_TO_BLOCK_LIST_BLOCK_PHONE_NUMBER_TITLE",
        @"Title for the 'block phone number' section of the 'add to block list' view.");
}

- (NSString *)phoneNumberButtonText
{
    return NSLocalizedString(@"BLOCK_LIST_VIEW_BLOCK_BUTTON", @"A label for the block button in the block list view");
}

- (NSString *)contactsSectionTitle
{
    return NSLocalizedString(@"SETTINGS_ADD_TO_BLOCK_LIST_BLOCK_CONTACT_TITLE",
        @"Title for the 'block contact' section of the 'add to block list' view.");
}

- (void)phoneNumberWasSelected:(NSString *)phoneNumber
{
    OWSAssert(phoneNumber.length > 0);

    __weak AddToBlockListViewController *weakSelf = self;
    [BlockListUIUtils showBlockPhoneNumberActionSheet:phoneNumber
                                   fromViewController:self
                                      blockingManager:self.contactsViewHelper.blockingManager
                                      contactsManager:self.contactsViewHelper.contactsManager
                                      completionBlock:^(BOOL isBlocked) {
                                          if (isBlocked) {
                                              [weakSelf.navigationController popViewControllerAnimated:YES];
                                          }
                                      }];
}

- (void)signalAccountWasSelected:(SignalAccount *)signalAccount
{
    OWSAssert(signalAccount);

    __weak AddToBlockListViewController *weakSelf = self;
    ContactsViewHelper *helper = self.contactsViewHelper;
    if ([helper isRecipientIdBlocked:signalAccount.recipientId]) {
        NSString *displayName = [helper.contactsManager displayNameForSignalAccount:signalAccount];
        UIAlertController *controller = [UIAlertController
            alertControllerWithTitle:NSLocalizedString(@"BLOCK_LIST_VIEW_ALREADY_BLOCKED_ALERT_TITLE",
                                         @"A title of the alert if user tries to block a "
                                         @"user who is already blocked.")
                             message:[NSString stringWithFormat:NSLocalizedString(@"BLOCK_LIST_VIEW_ALREADY_"
                                                                                  @"BLOCKED_ALERT_MESSAGE_"
                                                                                  @"FORMAT",
                                                                    @"A format for the message of the alert "
                                                                    @"if user tries to "
                                                                    @"block a user who is already blocked.  "
                                                                    @"Embeds {{the "
                                                                    @"blocked user's name or phone number}}."),
                                               displayName]
                      preferredStyle:UIAlertControllerStyleAlert];
        [controller addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil)
                                                       style:UIAlertActionStyleDefault
                                                     handler:nil]];
        [self presentViewController:controller animated:YES completion:nil];
        return;
    }
    [BlockListUIUtils showBlockSignalAccountActionSheet:signalAccount
                                     fromViewController:self
                                        blockingManager:helper.blockingManager
                                        contactsManager:helper.contactsManager
                                        completionBlock:^(BOOL isBlocked) {
                                            if (isBlocked) {
                                                [weakSelf.navigationController popViewControllerAnimated:YES];
                                            }
                                        }];
}

- (BOOL)shouldHideLocalNumber
{
    return YES;
}

- (BOOL)shouldHideContacts
{
    return NO;
}

- (BOOL)shouldValidatePhoneNumbers
{
    return NO;
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
