//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "BlockListViewController.h"
#import "AddToBlockListViewController.h"
#import "ContactsUpdater.h"
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
@property (nonatomic) NSDictionary<NSString *, Contact *> *contactMap;

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
    self.contacts = self.contactsManager.signalContacts;

    self.title
        = NSLocalizedString(@"SETTINGS_BLOCK_LIST_TITLE", @"Label for the block list section of the settings view");

    [self addNotificationListeners];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    [self refreshContacts];
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

- (nullable NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    switch (section) {
        case BlockListViewControllerSection_Add:
            return NSLocalizedString(
                                     @"SETTINGS_BLOCK_LIST_HEADER_TITLE", @"A header title for the block list table.");
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
            cell.textLabel.font = [UIFont ows_mediumFontWithSize:18.f];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        case BlockListViewControllerSection_BlockList: {
            NSString *displayName = [self displayNameForIndexPath:indexPath];
            cell.textLabel.text = displayName;
            cell.textLabel.font = [UIFont ows_mediumFontWithSize:18.f];
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
    PhoneNumber *parsedPhoneNumber = [PhoneNumber tryParsePhoneNumberFromUserSpecifiedText:phoneNumber];

    // Try to parse and present the phone number in E164.
    // It should already be in E164, so this should always work.
    // If an invalid or unparsable phone number is already in the block list,
    // present it as-is.
    NSString *displayName = (parsedPhoneNumber ? parsedPhoneNumber.toE164 : phoneNumber);
    Contact *contact = self.contactMap[displayName];
    if (contact && [contact fullName].length > 0) {
        displayName = [contact fullName];
    }

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
            NSString *displayName = [self displayNameForIndexPath:indexPath];
            [self showUnblockActionSheet:phoneNumber displayName:displayName];
            break;
        }
        default:
            OWSAssert(0);
    }
}

- (void)showUnblockActionSheet:(NSString *)phoneNumber displayName:(NSString *)displayName
{
    OWSAssert(phoneNumber.length > 0);
    OWSAssert(displayName.length > 0);

    NSString *title = [NSString stringWithFormat:NSLocalizedString(@"BLOCK_LIST_UNBLOCK_TITLE_FORMAT",
                                                     @"A format for the 'unblock phone number' action sheet title."),
                                displayName];

    UIAlertController *actionSheetController =
        [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleActionSheet];

    __weak BlockListViewController *weakSelf = self;
    UIAlertAction *unblockAction = [UIAlertAction
        actionWithTitle:NSLocalizedString(@"BLOCK_LIST_UNBLOCK_BUTTON", @"Button label for the 'unblock' button")
                  style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *_Nonnull action) {
                    [weakSelf unblockPhoneNumber:phoneNumber displayName:displayName];
                }];
    [actionSheetController addAction:unblockAction];

    UIAlertAction *dismissAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"TXT_CANCEL_TITLE", @"")
                                                            style:UIAlertActionStyleCancel
                                                          handler:nil];
    [actionSheetController addAction:dismissAction];

    [self presentViewController:actionSheetController animated:YES completion:nil];
}

- (void)unblockPhoneNumber:(NSString *)phoneNumber displayName:(NSString *)displayName
{
    [_blockingManager removeBlockedPhoneNumber:phoneNumber];

    UIAlertController *controller = [UIAlertController
        alertControllerWithTitle:NSLocalizedString(@"BLOCK_LIST_VIEW_UNBLOCKED_ALERT_TITLE",
                                     @"The title of the 'phone number unblocked' alert in the block view.")
                         message:[NSString stringWithFormat:NSLocalizedString(
                                                                @"BLOCK_LIST_VIEW_UNBLOCKED_ALERT_MESSAGE_FORMAT",
                                                                @"The message format of the 'phone number unblocked' "
                                                                @"alert in the block view. It is populated with the "
                                                                @"blocked phone number."),
                                           displayName]
                  preferredStyle:UIAlertControllerStyleAlert];

    [controller addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil)
                                                   style:UIAlertActionStyleDefault
                                                 handler:nil]];
    [self presentViewController:controller animated:YES completion:nil];
}

#pragma mark - Actions

- (void)blockedPhoneNumbersDidChange:(id)notification
{
    _blockedPhoneNumbers = [_blockingManager blockedPhoneNumbers];

    [self.tableView reloadData];
}

- (void)signalRecipientsDidChange:(NSNotification *)notification
{
    [self updateContacts];
}

- (void)updateContacts
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self.contacts = self.contactsManager.signalContacts;
        [self.tableView reloadData];
    });
}

- (void)refreshContacts
{
    [[ContactsUpdater sharedUpdater] updateSignalContactIntersectionWithABContacts:self.contactsManager.allContacts
        success:^{
            [self updateContacts];
        }
        failure:^(NSError *error) {
            DDLogError(@"%@ Error updating contacts", self.tag);
        }];
}

- (void)setContacts:(NSArray<Contact *> *)contacts
{
    _contacts = contacts;

    NSMutableDictionary<NSString *, Contact *> *contactMap = [NSMutableDictionary new];
    for (Contact *contact in contacts) {
        for (PhoneNumber *phoneNumber in contact.parsedPhoneNumbers) {
            NSString *phoneNumberE164 = phoneNumber.toE164;
            if (phoneNumberE164.length > 0) {
                contactMap[phoneNumberE164] = contact;
            }
        }
    }
    self.contactMap = contactMap;
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
