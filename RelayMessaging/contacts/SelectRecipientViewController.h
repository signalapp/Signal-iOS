//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <RelayMessaging/OWSViewController.h>

NS_ASSUME_NONNULL_BEGIN

@class RelayRecipient;
@class FLTag;

@protocol SelectRecipientViewControllerDelegate <NSObject>

//- (NSString *)phoneNumberSectionTitle;
//- (NSString *)phoneNumberButtonText;
- (NSString *)contactsSectionTitle;

//- (void)phoneNumberWasSelected:(NSString *)phoneNumber;
//- (BOOL)canSignalAccountBeSelected:(SignalAccount *)signalAccount;

-(void)relayTagWasSelected:(FLTag *)relayTag;
-(void)relayRecipientWasSelected:(RelayRecipient *)relayRecipient;

//- (nullable NSString *)accessoryMessageForSignalAccount:(SignalAccount *)signalAccount;

- (BOOL)shouldHideLocalNumber;

- (BOOL)shouldHideContacts;

//- (BOOL)shouldValidatePhoneNumbers;

@end

#pragma mark -

@class ContactsViewHelper;

@interface SelectRecipientViewController : OWSViewController

@property (nonatomic, weak) id<SelectRecipientViewControllerDelegate> delegate;

@property (nonatomic, readonly) ContactsViewHelper *contactsViewHelper;

@property (nonatomic) BOOL isPresentedInNavigationController;

@end

NS_ASSUME_NONNULL_END
