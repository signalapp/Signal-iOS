//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

@class ContactAccount;

@protocol SelectRecipientViewControllerDelegate <NSObject>

- (NSString *)phoneNumberSectionTitle;
- (NSString *)phoneNumberButtonText;
- (NSString *)contactsSectionTitle;

- (void)phoneNumberWasSelected:(NSString *)phoneNumber;

- (void)contactAccountWasSelected:(ContactAccount *)contactAccount;

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
