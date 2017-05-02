//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

@class SignalAccount;

@protocol SelectRecipientViewControllerDelegate <NSObject>

- (NSString *)phoneNumberSectionTitle;
- (NSString *)phoneNumberButtonText;
- (NSString *)contactsSectionTitle;

- (void)phoneNumberWasSelected:(NSString *)phoneNumber;

- (BOOL)canSignalAccountBeSelected:(SignalAccount *)signalAccount;

- (void)signalAccountWasSelected:(SignalAccount *)signalAccount;

- (nullable NSString *)accessoryMessageForSignalAccount:(SignalAccount *)signalAccount;

- (BOOL)shouldHideLocalNumber;

- (BOOL)shouldHideContacts;

- (BOOL)shouldValidatePhoneNumbers;

@end

#pragma mark -

@class ContactsViewHelper;

@interface SelectRecipientViewController : UIViewController

@property (nonatomic, weak) id<SelectRecipientViewControllerDelegate> delegate;

@property (nonatomic, readonly) ContactsViewHelper *contactsViewHelper;

@end
