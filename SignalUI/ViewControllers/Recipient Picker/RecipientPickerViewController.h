//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

#import <SignalUI/OWSViewController.h>

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

@property (nonatomic) UITableView *tableView;

- (void)reloadContent;

- (void)clearSearchText;

- (void)applyThemeToViewController:(UIViewController *)viewController;
- (void)removeThemeFromViewController:(UIViewController *)viewController;

@end

NS_ASSUME_NONNULL_END
