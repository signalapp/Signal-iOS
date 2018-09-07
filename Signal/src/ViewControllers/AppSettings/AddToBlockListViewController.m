//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "AddToBlockListViewController.h"
#import "BlockListUIUtils.h"
#import "ContactsViewHelper.h"
#import <SignalMessaging/OWSContactsManager.h>
#import <SignalServiceKit/SignalAccount.h>

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
    OWSAssertDebug(phoneNumber.length > 0);

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

- (BOOL)canSignalAccountBeSelected:(SignalAccount *)signalAccount
{
    OWSAssertDebug(signalAccount);

    ContactsViewHelper *helper = self.contactsViewHelper;
    return ![helper isRecipientIdBlocked:signalAccount.recipientId];
}

- (void)signalAccountWasSelected:(SignalAccount *)signalAccount
{
    OWSAssertDebug(signalAccount);

    __weak AddToBlockListViewController *weakSelf = self;
    ContactsViewHelper *helper = self.contactsViewHelper;
    if ([helper isRecipientIdBlocked:signalAccount.recipientId]) {
        OWSFailDebug(@"Cannot add already blocked user to block list.");
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

- (nullable NSString *)accessoryMessageForSignalAccount:(SignalAccount *)signalAccount
{
    return nil;
}

@end

NS_ASSUME_NONNULL_END
