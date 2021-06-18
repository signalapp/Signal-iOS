//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "BlockListViewController.h"
#import "BlockListUIUtils.h"
#import "ContactsViewHelper.h"
#import "PhoneNumber.h"
#import "Signal-Swift.h"
#import "UIFont+OWS.h"
#import "UIView+OWS.h"
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/OWSContactsManager.h>
#import <SignalMessaging/OWSTableViewController.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/OWSBlockingManager.h>
#import <SignalServiceKit/TSGroupThread.h>

NS_ASSUME_NONNULL_BEGIN

@interface BlockListViewController () <ContactsViewHelperObserver, AddToBlockListDelegate>

@property (nonatomic, readonly) OWSTableViewController2 *tableViewController;

@end

#pragma mark -

@implementation BlockListViewController

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

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    [self.tableViewController applyThemeToViewController:self];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];

    [self.tableViewController removeThemeFromViewController:self];
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
                    accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"add")
                                actionBlock:^{
                                    AddToBlockListViewController *vc = [AddToBlockListViewController new];
                                    vc.delegate = self;
                                    [weakSelf.navigationController pushViewController:vc animated:YES];
                                }]];
    [contents addSection:addSection];

    // "Blocklist" section

    NSMutableSet<SignalServiceAddress *> *blockedAddressesSet = [NSMutableSet new];
    for (NSString *phoneNumber in self.blockingManager.blockedPhoneNumbers) {
        [blockedAddressesSet addObject:[[SignalServiceAddress alloc] initWithPhoneNumber:phoneNumber]];
    }

    for (NSString *uuidString in self.blockingManager.blockedUUIDs) {
        [blockedAddressesSet addObject:[[SignalServiceAddress alloc] initWithUuidString:uuidString]];
    }

    NSArray<SignalServiceAddress *> *blockedAddresses =
        [blockedAddressesSet.allObjects sortedArrayUsingSelector:@selector(compare:)];
    if (blockedAddresses.count > 0) {
        OWSTableSection *blockedContactsSection = [OWSTableSection new];
        blockedContactsSection.headerTitle = NSLocalizedString(
            @"BLOCK_LIST_BLOCKED_USERS_SECTION", @"Section header for users that have been blocked");

        for (SignalServiceAddress *address in blockedAddresses) {
            [blockedContactsSection addItem:[OWSTableItem
                                                itemWithDequeueCellBlock:^(UITableView *tableView) {
                                                    ContactTableViewCell *cell = [tableView
                                                        dequeueReusableCellWithIdentifier:ContactTableViewCell
                                                                                              .reuseIdentifier];

                                                    [BlockListViewController.databaseStorage
                                                        readWithBlock:^(SDSAnyReadTransaction *transaction) {
                                                            ContactCellConfiguration *configuration =
                                                                [ContactCellConfiguration
                                                                         buildForAddress:address
                                                                    localUserDisplayMode:LocalUserDisplayModeAsUser
                                                                             transaction:transaction];
                                                            [cell configureWithConfiguration:configuration
                                                                                 transaction:transaction];
                                                        }];
                                                    cell.accessibilityIdentifier = ACCESSIBILITY_IDENTIFIER_WITH_NAME(
                                                        BlockListViewController, @"user");
                                                    return cell;
                                                }
                                                actionBlock:^{
                                                    [BlockListUIUtils showUnblockAddressActionSheet:address
                                                                                 fromViewController:weakSelf
                                                                                    completionBlock:^(BOOL isBlocked) {
                                                                                        [weakSelf updateTableContents];
                                                                                    }];
                                                }]];
        }
        [contents addSection:blockedContactsSection];
    }

    NSArray<TSGroupModel *> *blockedGroups = self.blockingManager.blockedGroups;
    if (blockedGroups.count > 0) {
        OWSTableSection *blockedGroupsSection = [OWSTableSection new];
        blockedGroupsSection.headerTitle = NSLocalizedString(
            @"BLOCK_LIST_BLOCKED_GROUPS_SECTION", @"Section header for groups that have been blocked");

        for (TSGroupModel *blockedGroup in blockedGroups) {
            UIImage *_Nullable image = blockedGroup.groupAvatarImage;
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
