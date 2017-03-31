//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "BlockListViewController.h"
#import "UIFont+OWS.h"
#import "PhoneNumber.h"
#import "AddToBlockListViewController.h"
#import <SignalServiceKit/TSBlockingManager.h>

NS_ASSUME_NONNULL_BEGIN

NSString * const kBlockListViewControllerCellIdentifier = @"kBlockListViewControllerCellIdentifier";

// TODO: We should label phone numbers with contact names where possible.
@interface BlockListViewController ()

@property (nonatomic, readonly) TSBlockingManager *blockingManager;
@property (nonatomic, readonly) NSArray<NSString *> *blockedPhoneNumbers;

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
    
    _blockingManager = [TSBlockingManager sharedManager];
    _blockedPhoneNumbers = [_blockingManager blockedPhoneNumbers];

    self.title = NSLocalizedString(@"SETTINGS_BLOCK_LIST_TITLE", @"");

    [self.tableView registerClass:[UITableViewCell class]
           forCellReuseIdentifier:kBlockListViewControllerCellIdentifier];

    [self addNotificationListeners];
}

- (void)addNotificationListeners
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(blockedPhoneNumbersDidChange:)
                                                 name:kNSNotificationName_BlockedPhoneNumbersDidChange
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
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kBlockListViewControllerCellIdentifier];
    OWSAssert(cell);
    
    switch (indexPath.section) {
        case BlockListViewControllerSection_Add:
            cell.textLabel.text = NSLocalizedString(
                                                    @"SETTINGS_BLOCK_LIST_ADD_BUTTON", @"A label for the 'add phone number' button in the block list table.");
            cell.textLabel.font = [UIFont ows_mediumFontWithSize:18.f];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        case BlockListViewControllerSection_BlockList: {
            NSString *phoneNumber = _blockedPhoneNumbers[(NSUInteger) indexPath.item];
            PhoneNumber *parsedPhoneNumber = [PhoneNumber tryParsePhoneNumberFromUserSpecifiedText:phoneNumber];
            // Try to parse and present the phone number in E164.
            // It should already be in E164, so this should always work.
            // If an invalid or unparsable phone number is already in the block list,
            // present it as-is.
            cell.textLabel.text = (parsedPhoneNumber
                                   ? parsedPhoneNumber.toE164
                                   : phoneNumber);
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
            [self showUnblockActionSheet:phoneNumber];
            break;
        }
        default:
            OWSAssert(0);
    }
}

- (void)showUnblockActionSheet:(NSString *)phoneNumber
{
    OWSAssert(phoneNumber.length > 0);

    PhoneNumber *parsedPhoneNumber = [PhoneNumber tryParsePhoneNumberFromUserSpecifiedText:phoneNumber];
    NSString *displayPhoneNumber = (parsedPhoneNumber ? parsedPhoneNumber.toE164 : phoneNumber);

    NSString *title = [NSString stringWithFormat:NSLocalizedString(@"BLOCK_LIST_UNBLOCK_TITLE_FORMAT",
                                                     @"A format for the 'unblock phone number' action sheet title."),
                                displayPhoneNumber];

    UIAlertController *actionSheetController =
        [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleActionSheet];

    __weak BlockListViewController *weakSelf = self;
    UIAlertAction *unblockAction = [UIAlertAction
        actionWithTitle:NSLocalizedString(@"BLOCK_LIST_UNBLOCK_BUTTON", @"Button label for the 'unblock' button")
                  style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *_Nonnull action) {
                    [weakSelf unblockPhoneNumber:phoneNumber displayPhoneNumber:displayPhoneNumber];
                }];
    [actionSheetController addAction:unblockAction];

    UIAlertAction *dismissAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"TXT_CANCEL_TITLE", @"")
                                                            style:UIAlertActionStyleCancel
                                                          handler:nil];
    [actionSheetController addAction:dismissAction];

    [self presentViewController:actionSheetController animated:YES completion:nil];
}

- (void)unblockPhoneNumber:(NSString *)phoneNumber displayPhoneNumber:(NSString *)displayPhoneNumber
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
                                           displayPhoneNumber]
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
