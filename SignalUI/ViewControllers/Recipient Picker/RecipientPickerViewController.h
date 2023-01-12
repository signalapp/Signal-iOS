//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <SignalUI/OWSViewControllerObjc.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_CLOSED_ENUM(NSUInteger, RecipientPickerViewControllerGroupsToShow) {
    RecipientPickerViewControllerGroupsToShow_ShowNoGroups = 0,
    RecipientPickerViewControllerGroupsToShow_ShowGroupsThatUserIsMemberOfWhenSearching,
    RecipientPickerViewControllerGroupsToShow_ShowAllGroupsWhenSearching,
};

typedef NS_CLOSED_ENUM(NSUInteger, RecipientPickerViewControllerSelectionMode) {
    RecipientPickerViewControllerSelectionModeDefault = 1,

    /// The .blocklist selection mode changes the behavior in a few ways:
    ///
    /// - If numbers aren't registered, allow them to be chosen. You may want to
    ///   block someone even if they aren't registered.
    ///
    /// - If numbers aren't registered, don't offer to invite them to Signal. If
    ///   you want to block someone, you probably don't want to invite them.
    RecipientPickerViewControllerSelectionModeBlocklist = 2,
};

@protocol RecipientPickerDelegate;

@class OWSInviteFlow;
@class PickedRecipient;
@class SignalAccount;

@interface RecipientPickerViewController : OWSViewControllerObjc

@property (nonatomic, weak) id<RecipientPickerDelegate> delegate;

/// Defaults to `YES`
@property (nonatomic) BOOL allowsAddByPhoneNumber;
/// Defaults to `YES`
@property (nonatomic) BOOL shouldHideLocalRecipient;
/// Defaults to `RecipientPickerViewControllerSelectionModeDefault`
@property (nonatomic) RecipientPickerViewControllerSelectionMode selectionMode;
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

// Swift interop

@property (nonatomic, nullable) OWSInviteFlow *inviteFlow;
- (NSArray<SignalAccount *> *)allSignalAccounts;

@end

NS_ASSUME_NONNULL_END
