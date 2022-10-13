//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <SignalUI/OWSViewController.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_CLOSED_ENUM(NSUInteger, RecipientPickerViewControllerGroupsToShow) {
    RecipientPickerViewControllerGroupsToShow_ShowNoGroups = 0,
    RecipientPickerViewControllerGroupsToShow_ShowGroupsThatUserIsMemberOfWhenSearching,
    RecipientPickerViewControllerGroupsToShow_ShowAllGroupsWhenSearching,
};

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
/// Defaults to `RecipientPickerViewControllerGroupsToShow_ShowGroupsThatUserIsMemberOfWhenSearching`
@property (nonatomic) RecipientPickerViewControllerGroupsToShow groupsToShow;
/// Defaults to `NO`
@property (nonatomic) BOOL shouldShowInvites;
/// Defaults to `YES`
@property (nonatomic) BOOL shouldShowAlphabetSlider;
/// Defaults to `NO`
@property (nonatomic) BOOL shouldShowNewGroup;
/// Defaults to `NO`
@property (nonatomic) BOOL shouldUseAsyncSelection;

@property (nonatomic, nullable) NSString *findByPhoneNumberButtonTitle;

@property (nonatomic, nullable) NSArray<PickedRecipient *> *pickedRecipients;

@property (nonatomic) UITableView *tableView;

- (void)reloadContent;

- (void)clearSearchText;

- (void)applyThemeToViewController:(UIViewController *)viewController;
- (void)removeThemeFromViewController:(UIViewController *)viewController;

@end

NS_ASSUME_NONNULL_END
