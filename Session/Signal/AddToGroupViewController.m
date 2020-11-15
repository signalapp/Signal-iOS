//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "AddToGroupViewController.h"
#import "BlockListUIUtils.h"

#import "Session-Swift.h"

#import <SignalUtilitiesKit/SignalAccount.h>

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
    OWSAssertDebug(phoneNumber.length > 0);

    __weak AddToGroupViewController *weakSelf = self;

    if ([SSKEnvironment.shared.blockingManager isRecipientIdBlocked:phoneNumber]) {
        [BlockListUIUtils showUnblockPhoneNumberActionSheet:phoneNumber
                                         fromViewController:self
                                            blockingManager:SSKEnvironment.shared.blockingManager
                                            completionBlock:^(BOOL isBlocked) {
                                                if (!isBlocked) {
                                                    [weakSelf addToGroup:phoneNumber];
                                                }
                                            }];
        return;
    }

    [self addToGroup:phoneNumber];
}

- (BOOL)canSignalAccountBeSelected:(SignalAccount *)signalAccount
{
    OWSAssertDebug(signalAccount);

    return ![self.addToGroupDelegate isRecipientGroupMember:signalAccount.recipientId];
}

- (void)signalAccountWasSelected:(SignalAccount *)signalAccount
{
    OWSAssertDebug(signalAccount);

    __weak AddToGroupViewController *weakSelf = self;
    if ([self.addToGroupDelegate isRecipientGroupMember:signalAccount.recipientId]) {
        OWSFailDebug(@"Cannot add user to group member if already a member.");
        return;
    }

    if ([SSKEnvironment.shared.blockingManager isRecipientIdBlocked:signalAccount.recipientId]) {
        [BlockListUIUtils showUnblockSignalAccountActionSheet:signalAccount
                                           fromViewController:self
                                              blockingManager:SSKEnvironment.shared.blockingManager
                                              completionBlock:^(BOOL isBlocked) {
                                                  if (!isBlocked) {
                                                      [weakSelf addToGroup:signalAccount.recipientId];
                                                  }
                                              }];
        return;
    }

    [self addToGroup:signalAccount.recipientId];
}

- (void)addToGroup:(NSString *)recipientId
{
    OWSAssertDebug(recipientId.length > 0);

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

- (nullable NSString *)accessoryMessageForSignalAccount:(SignalAccount *)signalAccount
{
    OWSAssertDebug(signalAccount);

    if ([self.addToGroupDelegate isRecipientGroupMember:signalAccount.recipientId]) {
        return NSLocalizedString(@"NEW_GROUP_MEMBER_LABEL", @"An indicator that a user is a member of the new group.");
    }

    return nil;
}

@end

NS_ASSUME_NONNULL_END
