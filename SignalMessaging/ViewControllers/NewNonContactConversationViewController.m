//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "NewNonContactConversationViewController.h"
#import "BlockListUIUtils.h"
#import "ContactsViewHelper.h"
#import <SignalMessaging/OWSContactsManager.h>
#import <SignalServiceKit/SignalAccount.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

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
    OWSFailDebug(@"Method should never be called.");

    return nil;
}

- (void)phoneNumberWasSelected:(NSString *)phoneNumber
{
    OWSAssertDebug(phoneNumber.length > 0);

    [self selectRecipientAddress:[[SignalServiceAddress alloc] initWithPhoneNumber:phoneNumber]];
}

- (void)signalAccountWasSelected:(SignalAccount *)signalAccount
{
    OWSAssertDebug(signalAccount);

    [self selectRecipientAddress:signalAccount.recipientAddress];
}

- (void)selectRecipientAddress:(SignalServiceAddress *)address
{
    OWSAssertDebug(address.isValid);

    [self.nonContactConversationDelegate recipientAddressWasSelected:address];
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
    OWSFailDebug(@"Method should never be called.");

    return NO;
}

- (nullable NSString *)accessoryMessageForSignalAccount:(SignalAccount *)signalAccount
{
    OWSFailDebug(@"Method should never be called.");

    return nil;
}

@end

NS_ASSUME_NONNULL_END
