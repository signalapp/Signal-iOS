//
// Copyright 2015 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "BlockListViewController.h"
#import "Signal-Swift.h"
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/OWSContactsManager.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/PhoneNumber.h>
#import <SignalServiceKit/TSGroupThread.h>
#import <SignalUI/BlockListUIUtils.h>
#import <SignalUI/ContactsViewHelper.h>
#import <SignalUI/OWSTableViewController.h>
#import <SignalUI/UIView+SignalUI.h>

NS_ASSUME_NONNULL_BEGIN

@interface BlockListViewController () <ContactsViewHelperObserver, AddToBlockListDelegate>

@property (nonatomic, readonly) OWSTableViewController2 *tableViewController;

@end

#pragma mark -

@implementation BlockListViewController

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    self.navbarBackgroundColorOverride = self.tableViewController.tableBackgroundColor;
    self.preferredNavigationBarStyle = OWSNavigationBarStyleBlur;
    return self;
}

- (void)loadView
{
    [super loadView];

    [self.contactsViewHelper addObserver:self];

    self.title
        = NSLocalizedString(@"SETTINGS_BLOCK_LIST_TITLE", @"Label for the block list section of the settings view");

    _tableViewController = [OWSTableViewController2 new];
    [self.view addSubview:self.tableViewController.view];
    [self addChildViewController:self.tableViewController];
    [_tableViewController.view autoPinEdgesToSuperviewEdges];
    self.tableViewController.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableViewController.tableView.estimatedRowHeight = 60;
    [self.tableViewController.tableView registerClass:[ContactTableViewCell class]
                               forCellReuseIdentifier:ContactTableViewCell.reuseIdentifier];

    [self updateTableContents];
}

- (void)applyTheme
{
    [super applyTheme];

    self.navbarBackgroundColorOverride = self.tableViewController.tableBackgroundColor;
    [[self owsNavigationController] updateNavbarAppearanceWithAnimated:NO];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    [self.tableViewController applyThemeToViewController:self];
    self.navbarBackgroundColorOverride = self.tableViewController.tableBackgroundColor;
}

#pragma mark - Table view data source

- (void)updateTableContents
{
    OWSTableContents *contents = [OWSTableContents new];

    __weak BlockListViewController *weakSelf = self;

    // "Add" section

    OWSTableSection *addSection = [OWSTableSection new];
    addSection.footerTitle = NSLocalizedString(
        @"BLOCK_USER_BEHAVIOR_EXPLANATION", @"An explanation of the consequences of blocking another user.");

    [addSection
        addItem:[OWSTableItem
                     disclosureItemWithText:NSLocalizedString(@"SETTINGS_BLOCK_LIST_ADD_BUTTON",
                                                @"A label for the 'add phone number' button in the block list table.")
                    accessibilityIdentifier:@"BlockListViewController.add"
                                actionBlock:^{
                                    AddToBlockListViewController *vc = [AddToBlockListViewController new];
                                    vc.delegate = self;
                                    [weakSelf.navigationController pushViewController:vc animated:YES];
                                }]];
    [contents addSection:addSection];

    // "Blocklist" section

    __block NSSet<SignalServiceAddress *> *blockedAddressSet = nil;
    __block NSArray<TSGroupModel *> *blockedGroupModels = nil;
    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *readTx) {
        blockedAddressSet = [self.blockingManager blockedAddressesWithTransaction:readTx];
        blockedGroupModels = [self.blockingManager blockedGroupModelsWithTransaction:readTx];
    }];

    NSArray<SignalServiceAddress *> *blockedAddresses =
        [blockedAddressSet.allObjects sortedArrayUsingSelector:@selector(compare:)];
    if (blockedAddresses.count > 0) {
        OWSTableSection *blockedContactsSection = [OWSTableSection new];
        blockedContactsSection.headerTitle = NSLocalizedString(
            @"BLOCK_LIST_BLOCKED_USERS_SECTION", @"Section header for users that have been blocked");

        for (SignalServiceAddress *address in blockedAddresses) {
            OWSTableItem *item = [OWSTableItem itemWithDequeueCellBlock:^UITableViewCell *(UITableView *tableView) {
                ContactTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:ContactTableViewCell.reuseIdentifier];
                ContactCellConfiguration *config = [[ContactCellConfiguration alloc] initWithAddress:address
                                                                                localUserDisplayMode:LocalUserDisplayModeAsUser];
                [weakSelf.databaseStorage readWithBlock:^(SDSAnyReadTransaction *readTx) {
                    [cell configureWithConfiguration:config transaction:readTx];
                }];
                cell.accessibilityIdentifier = @"BlockListViewController.user";
                return cell;
            } actionBlock:^{
                [BlockListUIUtils showUnblockAddressActionSheet:address fromViewController:weakSelf completionBlock:^(BOOL isBlocked) {
                    [weakSelf updateTableContents];
                }];
            }];

            [blockedContactsSection addItem:item];
        }
        [contents addSection:blockedContactsSection];
    }

    if (blockedGroupModels.count > 0) {
        OWSTableSection *blockedGroupsSection = [OWSTableSection new];
        blockedGroupsSection.headerTitle = NSLocalizedString(
            @"BLOCK_LIST_BLOCKED_GROUPS_SECTION", @"Section header for groups that have been blocked");

        for (TSGroupModel *blockedGroup in blockedGroupModels) {
            UIImage *_Nullable image = blockedGroup.avatarImage;
            if (!image) {
                image = [self.avatarBuilder avatarImageForGroupId:blockedGroup.groupId
                                                   diameterPoints:AvatarBuilder.standardAvatarSizePoints];
            }
            [blockedGroupsSection
                addItem:[OWSTableItem
                            itemWithCustomCellBlock:^{
                                OWSAvatarTableViewCell *cell = [OWSAvatarTableViewCell new];
                                [cell configureWithImage:image text:blockedGroup.groupNameOrDefault detailText:nil];
                                return cell;
                            }
                            actionBlock:^{
                                [BlockListUIUtils
                                    showUnblockGroupActionSheet:blockedGroup
                                             fromViewController:weakSelf
                                                completionBlock:^(BOOL isBlocked) { [weakSelf updateTableContents]; }];
                            }]];
        }
        [contents addSection:blockedGroupsSection];
    }

    self.tableViewController.contents = contents;
}

#pragma mark - ContactsViewHelperObserver

- (void)contactsViewHelperDidUpdateContacts
{
    [self updateTableContents];
}

#pragma mark - AddToBlockListDelegate

- (void)addToBlockListComplete
{
    [self.navigationController popToViewController:self animated:YES];
}

@end

NS_ASSUME_NONNULL_END
