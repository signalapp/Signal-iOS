//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import <SignalMessaging/OWSViewController.h>

NS_ASSUME_NONNULL_BEGIN

@class SignalAccount;
@class SignalServiceAddress;

@protocol SelectRecipientViewControllerDelegate <NSObject>

- (NSString *)phoneNumberSectionTitle;
- (NSString *)phoneNumberButtonText;
- (NSString *)contactsSectionTitle;

- (void)addressWasSelected:(SignalServiceAddress *)address;

- (BOOL)canSignalAccountBeSelected:(SignalAccount *)signalAccount;

- (void)signalAccountWasSelected:(SignalAccount *)signalAccount;

- (nullable NSString *)accessoryMessageForSignalAccount:(SignalAccount *)signalAccount;

- (BOOL)shouldHideLocalNumber;

- (BOOL)shouldHideContacts;

- (BOOL)shouldValidatePhoneNumbers;

@end

#pragma mark -

@class ContactsViewHelper;

@interface SelectRecipientViewController : OWSViewController

@property (nonatomic, weak) id<SelectRecipientViewControllerDelegate> delegate;

@property (nonatomic, readonly) ContactsViewHelper *contactsViewHelper;

@property (nonatomic) BOOL isPresentedInNavigationController;

@end

NS_ASSUME_NONNULL_END
