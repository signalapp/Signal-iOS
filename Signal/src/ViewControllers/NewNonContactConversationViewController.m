//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "NewNonContactConversationViewController.h"
#import "BlockListUIUtils.h"
#import "ContactsViewHelper.h"
#import "OWSContactsManager.h"
#import <SignalServiceKit/SignalAccount.h>

NS_ASSUME_NONNULL_BEGIN

@interface NewNonContactConversationViewController () <SelectRecipientViewControllerDelegate>

@end

#pragma mark -

@implementation NewNonContactConversationViewController

- (void)loadView
{
    self.delegate = self;

    [super loadView];

    self.title = NSLocalizedString(
        @"NEW_NONCONTACT_CONVERSATION_VIEW_TITLE", @"Title for the 'new non-contact conversation' view.");
}

- (NSString *)phoneNumberSectionTitle
{
    return nil;
}

- (NSString *)phoneNumberButtonText
{
    return NSLocalizedString(@"NEW_NONCONTACT_CONVERSATION_VIEW_BUTTON",
        @"A label for the 'add by phone number' button in the 'new non-contact conversation' view");
}

- (NSString *)contactsSectionTitle
{
    OWSAssert(0);

    return nil;
}

- (void)phoneNumberWasSelected:(NSString *)phoneNumber
{
    OWSAssert(phoneNumber.length > 0);

    __weak NewNonContactConversationViewController *weakSelf = self;
    ContactsViewHelper *helper = self.contactsViewHelper;
    if ([helper isRecipientIdBlocked:phoneNumber]) {
        [BlockListUIUtils showUnblockPhoneNumberActionSheet:phoneNumber
                                         fromViewController:self
                                            blockingManager:helper.blockingManager
                                            contactsManager:helper.contactsManager
                                            completionBlock:^(BOOL isBlocked) {
                                                if (!isBlocked) {
                                                    [weakSelf selectRecipient:phoneNumber];
                                                }
                                            }];
    } else {
        [self selectRecipient:phoneNumber];
    }
}

- (void)signalAccountWasSelected:(SignalAccount *)signalAccount
{
    OWSAssert(signalAccount);

    __weak NewNonContactConversationViewController *weakSelf = self;
    ContactsViewHelper *helper = self.contactsViewHelper;
    if ([helper isRecipientIdBlocked:signalAccount.recipientId]) {
        [BlockListUIUtils showUnblockSignalAccountActionSheet:signalAccount
                                           fromViewController:self
                                              blockingManager:helper.blockingManager
                                              contactsManager:helper.contactsManager
                                              completionBlock:^(BOOL isBlocked) {
                                                  if (!isBlocked) {
                                                      [weakSelf selectRecipient:signalAccount.recipientId];
                                                  }
                                              }];
    } else {
        [self selectRecipient:signalAccount.recipientId];
    }
}

- (void)selectRecipient:(NSString *)recipientId
{
    OWSAssert(recipientId.length > 0);

    [self.nonContactConversationDelegate recipientIdWasSelected:recipientId];
}

- (BOOL)shouldHideLocalNumber
{
    return NO;
}

- (BOOL)shouldHideContacts
{
    return YES;
}

- (BOOL)shouldValidatePhoneNumbers
{
    return YES;
}

- (BOOL)canSignalAccountBeSelected:(SignalAccount *)signalAccount
{
    OWSAssert(0);

    return NO;
}

- (nullable NSString *)accessoryMessageForSignalAccount:(SignalAccount *)signalAccount
{
    OWSAssert(0);

    return nil;
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
