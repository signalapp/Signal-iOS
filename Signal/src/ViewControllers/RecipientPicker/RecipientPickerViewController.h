//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import <SignalMessaging/OWSViewController.h>

NS_ASSUME_NONNULL_BEGIN

@protocol RecipientPickerDelegate;

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
/// Defaults to `NO`
@property (nonatomic) BOOL shouldShowNewGroup;
/// Defaults to `NO`
@property (nonatomic) BOOL showUseAsyncSelection;

@property (nonatomic, nullable) NSString *findByPhoneNumberButtonTitle;

@property (nonatomic, nullable) NSArray<PickedRecipient *> *pickedRecipients;

- (void)reloadContent;

- (void)clearSearchText;

@end

NS_ASSUME_NONNULL_END
