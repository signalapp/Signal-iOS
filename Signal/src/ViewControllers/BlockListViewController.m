//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "BlockListViewController.h"
#import "AddToBlockListViewController.h"
#import "BlockListUIUtils.h"
#import "Environment.h"
#import "OWSContactsManager.h"
#import "PhoneNumber.h"
#import "UIFont+OWS.h"
#import <SignalServiceKit/OWSBlockingManager.h>

NS_ASSUME_NONNULL_BEGIN

@interface BlockListViewController ()

@property (nonatomic, readonly) OWSBlockingManager *blockingManager;
@property (nonatomic, readonly) NSArray<NSString *> *blockedPhoneNumbers;

@property (nonatomic, readonly) OWSContactsManager *contactsManager;
@property (nonatomic) NSArray<Contact *> *contacts;

@end

#pragma mark -

typedef NS_ENUM(NSInteger, BlockListViewControllerSection) {
    BlockListViewControllerSection_Add,
    BlockListViewControllerSection_BlockList,
    BlockListViewControllerSection_Count // meta section
};

@implementation BlockListViewController

- (instancetype)init
{
    return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)loadView
{
    [super loadView];
    
    _blockingManager = [OWSBlockingManager sharedManager];
    _blockedPhoneNumbers = [_blockingManager blockedPhoneNumbers];
    _contactsManager = [Environment getCurrent].contactsManager;
    self.contacts = [self.contactsManager.signalContacts copy];

    self.title
        = NSLocalizedString(@"SETTINGS_BLOCK_LIST_TITLE", @"Label for the block list section of the settings view");

    [self addNotificationListeners];
}

- (void)addNotificationListeners
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(blockedPhoneNumbersDidChange:)
                                                 name:kNSNotificationName_BlockedPhoneNumbersDidChange
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(signalRecipientsDidChange:)
                                                 name:OWSContactsManagerSignalRecipientsDidChangeNotification
                                               object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self.navigationController.navigationBar setTranslucent:NO];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return BlockListViewControllerSection_Count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    switch (section) {
        case BlockListViewControllerSection_Add:
            return 1;
        case BlockListViewControllerSection_BlockList:
            return (NSInteger) _blockedPhoneNumbers.count;
        default:
            OWSAssert(0);
            return 0;
    }
}

- (nullable NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    switch (section) {
        case BlockListViewControllerSection_Add:
            return NSLocalizedString(@"BLOCK_BEHAVIOR_EXPLANATION",
                                     @"An explanation of the consequences of blocking another user.");
       default:
            return nil;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [UITableViewCell new];
    OWSAssert(cell);
    
    switch (indexPath.section) {
        case BlockListViewControllerSection_Add:
            cell.textLabel.text = NSLocalizedString(
                                                    @"SETTINGS_BLOCK_LIST_ADD_BUTTON", @"A label for the 'add phone number' button in the block list table.");
            cell.textLabel.font = [UIFont ows_regularFontWithSize:18.f];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        case BlockListViewControllerSection_BlockList: {
            NSString *displayName = [self displayNameForIndexPath:indexPath];
            cell.textLabel.text = displayName;
            cell.textLabel.font = [UIFont ows_regularFontWithSize:18.f];
            cell.accessoryType = UITableViewCellAccessoryCheckmark;
            break;
        }
        default:
            OWSAssert(0);
            return 0;
    }
    
    return cell;
}

- (NSString *)displayNameForIndexPath:(NSIndexPath *)indexPath
{
    NSString *phoneNumber = _blockedPhoneNumbers[(NSUInteger)indexPath.item];
    NSString *displayName = [_contactsManager displayNameForPhoneIdentifier:phoneNumber];
    return displayName;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    switch (indexPath.section) {
        case BlockListViewControllerSection_Add:
        {
            AddToBlockListViewController *vc = [[AddToBlockListViewController alloc] init];
            NSAssert(self.navigationController != nil, @"Navigation controller must not be nil");
            NSAssert(vc != nil, @"Privacy Settings View Controller must not be nil");
            [self.navigationController pushViewController:vc animated:YES];
            break;
        }
        case BlockListViewControllerSection_BlockList: {
            NSString *phoneNumber = _blockedPhoneNumbers[(NSUInteger)indexPath.item];
            [BlockListUIUtils showUnblockPhoneNumberActionSheet:phoneNumber
                                             fromViewController:self
                                                blockingManager:_blockingManager
                                                contactsManager:_contactsManager
                                                completionBlock:nil];
            break;
        }
        default:
            OWSAssert(0);
    }
}

#pragma mark - Actions

- (void)blockedPhoneNumbersDidChange:(id)notification
{
    dispatch_async(dispatch_get_main_queue(), ^{
        _blockedPhoneNumbers = [_blockingManager blockedPhoneNumbers];

        [self.tableView reloadData];
    });
}

- (void)signalRecipientsDidChange:(NSNotification *)notification
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateContacts];
    });
}

- (void)updateContacts
{
    OWSAssert([NSThread isMainThread]);

    self.contacts = [self.contactsManager.signalContacts copy];
    [self.tableView reloadData];
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
