//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "BlockListViewController.h"
#import "AddToBlockListViewController.h"
#import "BlockListUIUtils.h"
#import "ContactsViewHelper.h"
#import "Environment.h"
#import "OWSContactsManager.h"
#import "OWSTableViewController.h"
#import "PhoneNumber.h"
#import "UIFont+OWS.h"
#import "UIView+OWS.h"
#import <SignalServiceKit/OWSBlockingManager.h>

NS_ASSUME_NONNULL_BEGIN

@interface BlockListViewController () <ContactsViewHelperDelegate>

@property (nonatomic, readonly) ContactsViewHelper *contactsViewHelper;

@property (nonatomic, readonly) OWSTableViewController *tableViewController;

@end

#pragma mark -

@implementation BlockListViewController

- (void)loadView
{
    [super loadView];

    _contactsViewHelper = [ContactsViewHelper new];
    _contactsViewHelper.delegate = self;

    self.title
        = NSLocalizedString(@"SETTINGS_BLOCK_LIST_TITLE", @"Label for the block list section of the settings view");

    _tableViewController = [OWSTableViewController new];
    [self.view addSubview:self.tableViewController.view];
    [_tableViewController.view autoPinWidthToSuperview];
    [_tableViewController.view autoPinToTopLayoutGuideOfViewController:self withInset:0];
    [_tableViewController.view autoPinToBottomLayoutGuideOfViewController:self withInset:0];

    [self updateTableContents];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self.navigationController.navigationBar setTranslucent:NO];
}

#pragma mark - Table view data source

- (void)updateTableContents
{
    OWSTableContents *contents = [OWSTableContents new];

    __weak BlockListViewController *weakSelf = self;
    ContactsViewHelper *helper = self.contactsViewHelper;

    // Add section

    OWSTableSection *addSection = [OWSTableSection new];
    addSection.footerTitle = NSLocalizedString(
        @"BLOCK_BEHAVIOR_EXPLANATION", @"An explanation of the consequences of blocking another user.");

    [addSection addItem:[OWSTableItem itemWithCustomCellBlock:^{
        UITableViewCell *cell = [UITableViewCell new];
        cell.textLabel.text = NSLocalizedString(
            @"SETTINGS_BLOCK_LIST_ADD_BUTTON", @"A label for the 'add phone number' button in the block list table.");
        cell.textLabel.font = [UIFont ows_regularFontWithSize:18.f];
        cell.textLabel.textColor = [UIColor blackColor];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
                            actionBlock:^{
                                AddToBlockListViewController *vc = [[AddToBlockListViewController alloc] init];
                                NSAssert(self.navigationController != nil, @"Navigation controller must not be nil");
                                NSAssert(vc != nil, @"Privacy Settings View Controller must not be nil");
                                [weakSelf.navigationController pushViewController:vc animated:YES];
                            }]];
    [contents addSection:addSection];

    // Blocklist section

    OWSTableSection *blocklistSection = [OWSTableSection new];
    NSArray<NSString *> *blockedPhoneNumbers =
        [helper.blockedPhoneNumbers sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *phoneNumber in blockedPhoneNumbers) {
        [blocklistSection addItem:[OWSTableItem itemWithCustomCellBlock:^{
            // TODO: Use ContactTableViewCell.
            UITableViewCell *cell = [UITableViewCell new];
            NSString *displayName = [helper.contactsManager displayNameForPhoneIdentifier:phoneNumber];
            cell.textLabel.text = displayName;
            cell.textLabel.font = [UIFont ows_regularFontWithSize:18.f];
            cell.accessoryType = UITableViewCellAccessoryCheckmark;
            cell.textLabel.textColor = [UIColor blackColor];
            return cell;
        }
                                      actionBlock:^{
                                          [BlockListUIUtils showUnblockPhoneNumberActionSheet:phoneNumber
                                                                           fromViewController:weakSelf
                                                                              blockingManager:helper.blockingManager
                                                                              contactsManager:helper.contactsManager
                                                                              completionBlock:nil];
                                      }]];
    }
    [contents addSection:blocklistSection];

    self.tableViewController.contents = contents;
}

#pragma mark - ContactsViewHelperDelegate

- (void)contactsViewHelperDidUpdateContacts
{
    [self updateTableContents];
}

- (BOOL)shouldHideLocalNumber
{
    return YES;
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end

NS_ASSUME_NONNULL_END
