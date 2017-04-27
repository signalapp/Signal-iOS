//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "ShowGroupMembersViewController.h"
#import "BlockListUIUtils.h"
#import "ContactTableViewCell.h"
#import "Environment.h"
#import "Signal-Swift.h"
#import "SignalsViewController.h"
#import "UIUtil.h"
#import <AddressBookUI/AddressBookUI.h>
#import <SignalServiceKit/OWSBlockingManager.h>

NS_ASSUME_NONNULL_BEGIN

static NSString *const kUnwindToMessagesViewSegue = @"UnwindToMessagesViewSegue";

@interface ShowGroupMembersViewController ()

@property GroupContactsResult *groupContacts;
@property TSGroupThread *thread;
@property (nonatomic, readonly) OWSContactsManager *_Nonnull contactsManager;

@property (nonatomic, readonly) OWSBlockingManager *blockingManager;
@property (nonatomic, readonly) NSArray<NSString *> *blockedPhoneNumbers;

@end

@implementation ShowGroupMembersViewController

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    [self commonInit];

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (!self) {
        return self;
    }

    [self commonInit];

    return self;
}


- (void)commonInit
{
    _blockingManager = [OWSBlockingManager sharedManager];
    _blockedPhoneNumbers = [_blockingManager blockedPhoneNumbers];
    _contactsManager = [Environment getCurrent].contactsManager;

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

- (void)blockedPhoneNumbersDidChange:(id)notification
{
    dispatch_async(dispatch_get_main_queue(), ^{
        _blockedPhoneNumbers = [_blockingManager blockedPhoneNumbers];

        [self.tableView reloadData];
    });
}

- (void)configWithThread:(TSGroupThread *)gThread {
    _thread = gThread;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.navigationController.navigationBar setTranslucent:NO];

    self.title = _thread.groupModel.groupName;

    [self initializeTableView];

    self.groupContacts =
        [[GroupContactsResult alloc] initWithMembersId:self.thread.groupModel.groupMemberIds without:nil];
    __weak ShowGroupMembersViewController *weakSelf = self;
    [self.contactsManager.getObservableContacts watchLatestValue:^(id latestValue) {
        ShowGroupMembersViewController *strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        strongSelf.groupContacts =
            [[GroupContactsResult alloc] initWithMembersId:strongSelf.thread.groupModel.groupMemberIds without:nil];
        [strongSelf.tableView reloadData];
    }
                                                        onThread:[NSThread mainThread]
                                                  untilCancelled:nil];
}

#pragma mark - Initializers

- (void)initializeTableView {
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
    [self.tableView registerClass:[ContactTableViewCell class]
           forCellReuseIdentifier:kContactsTable_CellReuseIdentifier];
}

#pragma mark - Actions

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)[self.groupContacts numberOfMembers] + 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{

    if (indexPath.row == 0) {
        UITableViewCell *cell = [UITableViewCell new];
        cell.textLabel.text      = NSLocalizedString(@"GROUP_MEMBERS_HEADER", @"header for table which lists the members of this group thread");
        cell.textLabel.textColor = [UIColor lightGrayColor];
        cell.selectionStyle      = UITableViewCellSelectionStyleNone;
        cell.userInteractionEnabled = NO;
        return cell;
    }

    // Adjust index path for the header row.
    indexPath = [NSIndexPath indexPathForRow:indexPath.row - 1 inSection:indexPath.section];

    ContactTableViewCell *cell = [ContactTableViewCell new];

    if ([self.groupContacts isContactAt:indexPath]) {
        Contact *contact = [self contactForIndexPath:indexPath];

        BOOL isBlocked = [self isContactBlocked:contact];
        if (isBlocked) {
            cell.accessoryMessage
                = NSLocalizedString(@"CONTACT_CELL_IS_BLOCKED", @"An indicator that a contact has been blocked.");
        } else {
            OWSAssert(cell.accessoryMessage == nil);
        }
        [cell configureWithContact:contact contactsManager:self.contactsManager];
    } else {
        NSString *recipientId = [self.groupContacts identifierFor:indexPath];
        BOOL isBlocked = [self isRecipientIdBlocked:recipientId];
        if (isBlocked) {
            cell.accessoryMessage
                = NSLocalizedString(@"CONTACT_CELL_IS_BLOCKED", @"An indicator that a contact has been blocked.");
        } else {
            OWSAssert(cell.accessoryMessage == nil);
        }
        [cell configureWithRecipientId:recipientId contactsManager:self.contactsManager];
    }
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.row == 0) {
        return 45.f;
    } else {
        return [ContactTableViewCell rowHeight];
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row == 0) {
        OWSAssert(0);
        return;
    }

    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    // Adjust index path for the header row.
    indexPath = [NSIndexPath indexPathForRow:indexPath.row - 1 inSection:indexPath.section];

    UIAlertController *actionSheetController =
        [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];

    [actionSheetController
        addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"GROUP_MEMBERS_VIEW_CONTACT_INFO",
                                                     @"Button label for the 'show contact info' button")
                                           style:UIAlertActionStyleDefault
                                         handler:^(UIAlertAction *_Nonnull action) {
                                             [self showContactInfoViewForMember:indexPath];
                                         }]];

    BOOL isBlocked;
    if ([self.groupContacts isContactAt:indexPath]) {
        Contact *contact = [self contactForIndexPath:indexPath];

        isBlocked = [self isContactBlocked:contact];
        if (isBlocked) {
            [actionSheetController
                addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"BLOCK_LIST_UNBLOCK_BUTTON",
                                                             @"Button label for the 'unblock' button")
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction *_Nonnull action) {
                                                     [BlockListUIUtils
                                                         showUnblockContactActionSheet:contact
                                                                    fromViewController:self
                                                                       blockingManager:self.blockingManager
                                                                       contactsManager:self.contactsManager
                                                                       completionBlock:nil];
                                                 }]];
        } else {
            [actionSheetController
                addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"BLOCK_LIST_BLOCK_BUTTON",
                                                             @"Button label for the 'block' button")
                                                   style:UIAlertActionStyleDestructive
                                                 handler:^(UIAlertAction *_Nonnull action) {
                                                     [BlockListUIUtils showBlockContactActionSheet:contact
                                                                                fromViewController:self
                                                                                   blockingManager:self.blockingManager
                                                                                   contactsManager:self.contactsManager
                                                                                   completionBlock:nil];
                                                 }]];
        }
    } else {
        NSString *recipientId = [self.groupContacts identifierFor:indexPath];
        isBlocked = [self isRecipientIdBlocked:recipientId];
        if (isBlocked) {
            [actionSheetController
                addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"BLOCK_LIST_UNBLOCK_BUTTON",
                                                             @"Button label for the 'unblock' button")
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction *_Nonnull action) {
                                                     [BlockListUIUtils
                                                         showUnblockPhoneNumberActionSheet:recipientId
                                                                        fromViewController:self
                                                                           blockingManager:self.blockingManager
                                                                           contactsManager:self.contactsManager
                                                                           completionBlock:nil];
                                                 }]];
        } else {
            [actionSheetController
                addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"BLOCK_LIST_BLOCK_BUTTON",
                                                             @"Button label for the 'block' button")
                                                   style:UIAlertActionStyleDestructive
                                                 handler:^(UIAlertAction *_Nonnull action) {
                                                     [BlockListUIUtils
                                                         showBlockPhoneNumberActionSheet:recipientId
                                                                      fromViewController:self
                                                                         blockingManager:self.blockingManager
                                                                         contactsManager:self.contactsManager
                                                                         completionBlock:nil];
                                                 }]];
        }
    }

    if (!isBlocked) {
        [actionSheetController
            addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"GROUP_MEMBERS_SEND_MESSAGE",
                                                         @"Button label for the 'send message to group member' button")
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *_Nonnull action) {
                                                 [self showConversationViewForMember:indexPath];
                                             }]];
        [actionSheetController
            addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"GROUP_MEMBERS_CALL",
                                                         @"Button label for the 'call group member' button")
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *_Nonnull action) {
                                                 [self callMember:indexPath];
                                             }]];
    }

    UIAlertAction *dismissAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"TXT_CANCEL_TITLE", @"")
                                                            style:UIAlertActionStyleCancel
                                                          handler:nil];
    [actionSheetController addAction:dismissAction];

    [self presentViewController:actionSheetController animated:YES completion:nil];
}

- (void)showContactInfoViewForMember:(NSIndexPath *)indexPath
{
    if ([self.groupContacts isContactAt:indexPath]) {
        ABPersonViewController *view = [[ABPersonViewController alloc] init];

        Contact *contact = [self.groupContacts contactFor:indexPath];
        ABAddressBookRef addressBookRef = ABAddressBookCreateWithOptions(NULL, nil);
        view.displayedPerson
            = ABAddressBookGetPersonWithRecordID(addressBookRef, contact.recordID); // Assume person is already defined.
        view.allowsActions = NO;
        view.allowsEditing = YES;

        [self.navigationController pushViewController:view animated:YES];
    } else {
        ABUnknownPersonViewController *view = [[ABUnknownPersonViewController alloc] init];

        ABRecordRef aContact = ABPersonCreate();
        CFErrorRef anError   = NULL;

        ABMultiValueRef phone = ABMultiValueCreateMutable(kABMultiStringPropertyType);
        ABMultiValueAddValueAndLabel(phone,
            (__bridge CFTypeRef)[self.tableView cellForRowAtIndexPath:indexPath].textLabel.text,
            kABPersonPhoneMainLabel,
            NULL);

        ABRecordSetValue(aContact, kABPersonPhoneProperty, phone, &anError);
        CFRelease(phone);

        if (!anError && aContact) {
            view.displayedPerson           = aContact; // Assume person is already defined.
            view.allowsAddingToAddressBook = YES;
            [self.navigationController pushViewController:view animated:YES];
        }
    }
}

- (void)showConversationViewForMember:(NSIndexPath *)indexPath
{
    NSString *recipientId;
    if ([self.groupContacts isContactAt:indexPath]) {
        Contact *contact = [self.groupContacts contactFor:indexPath];
        recipientId = [[contact textSecureIdentifiers] firstObject];
    } else {
        recipientId = [self.groupContacts identifierFor:indexPath];
    }
    [Environment messageIdentifier:recipientId withCompose:YES];
}

- (void)callMember:(NSIndexPath *)indexPath
{
    NSString *recipientId;
    if ([self.groupContacts isContactAt:indexPath]) {
        Contact *contact = [self.groupContacts contactFor:indexPath];
        recipientId = [[contact textSecureIdentifiers] firstObject];
    } else {
        recipientId = [self.groupContacts identifierFor:indexPath];
    }
    [Environment callUserWithIdentifier:recipientId];
}

- (Contact *)contactForIndexPath:(NSIndexPath *)indexPath {
    Contact *contact = [self.groupContacts contactFor:indexPath];
    return contact;
}

- (BOOL)isContactBlocked:(Contact *)contact
{
    if (contact.parsedPhoneNumbers.count < 1) {
        // Do not consider contacts without any valid phone numbers to be blocked.
        return NO;
    }

    for (PhoneNumber *phoneNumber in contact.parsedPhoneNumbers) {
        if ([_blockedPhoneNumbers containsObject:phoneNumber.toE164]) {
            return YES;
        }
    }

    return NO;
}

- (BOOL)isRecipientIdBlocked:(NSString *)recipientId
{
    return [_blockedPhoneNumbers containsObject:recipientId];
}

@end

NS_ASSUME_NONNULL_END
