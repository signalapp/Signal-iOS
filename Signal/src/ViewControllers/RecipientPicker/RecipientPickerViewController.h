//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import <SignalMessaging/OWSViewController.h>

NS_ASSUME_NONNULL_BEGIN

@protocol RecipientPickerDelegate;

@class ContactsViewHelper;
@class PickedRecipient;

@interface RecipientPickerViewController : OWSViewController

@property (nonatomic, weak) id<RecipientPickerDelegate> delegate;

/// Defaults to `YES`
@property (nonatomic) BOOL allowsAddByPhoneNumber;
/// Defaults to `YES`
@property (nonatomic) BOOL shouldHideLocalRecipient;
/// Defaults to `YES`
@property (nonatomic) BOOL allowsSelectingUnregisteredPhoneNumbers;
/// Defaults to `YES`
@property (nonatomic) BOOL shouldShowGroups;
/// Defaults to `NO`
@property (nonatomic) BOOL shouldShowInvites;
/// Defaults to `YES`
@property (nonatomic) BOOL shouldShowAlphabetSlider;

@property (nonatomic, nullable) NSString *findByPhoneNumberButtonTitle;

@property (nonatomic, readonly) ContactsViewHelper *contactsViewHelper;

@property (nonatomic, nullable) NSArray<PickedRecipient *> *pickedRecipients;

@end

NS_ASSUME_NONNULL_END
