//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "ShowGroupMembersViewController.h"
#import "SignalsViewController.h"
#import "OWSContactsManager.h"
#import "Environment.h"
#import "GroupContactsResult.h"
#import "UIUtil.h"
#import "UIViewController+OWS.h"
#import <AddressBookUI/AddressBookUI.h>

NS_ASSUME_NONNULL_BEGIN

static NSString *const kUnwindToMessagesViewSegue = @"UnwindToMessagesViewSegue";

@interface ShowGroupMembersViewController ()

@property GroupContactsResult *groupContacts;
@property TSGroupThread *thread;
@property (nonatomic, readonly) OWSContactsManager *_Nonnull contactsManager;

@end

@implementation ShowGroupMembersViewController

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    _contactsManager = [Environment getCurrent].contactsManager;

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (!self) {
        return self;
    }

    _contactsManager = [Environment getCurrent].contactsManager;

    return self;
}

- (void)configWithThread:(TSGroupThread *)gThread {
    _thread = gThread;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.navigationController.navigationBar setTranslucent:NO];

    self.title = _thread.groupModel.groupName;

    [self useOWSBackButton];

    [self initializeTableView];

    self.groupContacts =
        [[GroupContactsResult alloc] initWithMembersId:self.thread.groupModel.groupMemberIds without:nil];

    [self.contactsManager.getObservableContacts watchLatestValue:^(id latestValue) {
        self.groupContacts =
            [[GroupContactsResult alloc] initWithMembersId:self.thread.groupModel.groupMemberIds without:nil];
        [self.tableView reloadData];
    }
                                                        onThread:[NSThread mainThread]
                                                  untilCancelled:nil];
}

#pragma mark - Initializers

- (void)initializeTableView {
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
}

#pragma mark - Actions

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)[self.groupContacts numberOfMembers] + 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"SearchCell"];

    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                      reuseIdentifier:indexPath.row == 0 ? @"HeaderCell" : @"GroupSearchCell"];
    }
    if (indexPath.row > 0) {
        NSIndexPath *relativeIndexPath = [NSIndexPath indexPathForRow:indexPath.row - 1 inSection:indexPath.section];
        if ([self.groupContacts isContactAtIndexPath:relativeIndexPath]) {
            Contact *contact              = [self contactForIndexPath:relativeIndexPath];
            cell.textLabel.attributedText =
                [self.contactsManager formattedFullNameForContact:contact font:cell.textLabel.font];
        } else {
            cell.textLabel.text = [self.groupContacts identifierForIndexPath:relativeIndexPath];
        }
    } else {
        cell.textLabel.text      = NSLocalizedString(@"GROUP_MEMBERS_HEADER", @"header for table which lists the members of this group thread");
        cell.textLabel.textColor = [UIColor lightGrayColor];
        cell.selectionStyle      = UITableViewCellSelectionStyleNone;
        cell.userInteractionEnabled = NO;
    }

    tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSIndexPath *relativeIndexPath = [NSIndexPath indexPathForRow:indexPath.row - 1 inSection:indexPath.section];

    if (indexPath.row > 0 && [self.groupContacts isContactAtIndexPath:relativeIndexPath]) {
        ABPersonViewController *view = [[ABPersonViewController alloc] init];

        Contact *contact                = [self.groupContacts contactForIndexPath:relativeIndexPath];
        ABAddressBookRef addressBookRef = ABAddressBookCreateWithOptions(NULL, nil);
        view.displayedPerson =
            ABAddressBookGetPersonWithRecordID(addressBookRef, contact.recordID); // Assume person is already defined.
        view.allowsActions = NO;
        view.allowsEditing = YES;

        [self.navigationController pushViewController:view animated:YES];
    } else {
        ABUnknownPersonViewController *view = [[ABUnknownPersonViewController alloc] init];

        ABRecordRef aContact = ABPersonCreate();
        CFErrorRef anError   = NULL;

        ABMultiValueRef phone = ABMultiValueCreateMutable(kABMultiStringPropertyType);
        ABMultiValueAddValueAndLabel(
            phone,
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

    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (Contact *)contactForIndexPath:(NSIndexPath *)indexPath {
    Contact *contact = [self.groupContacts contactForIndexPath:indexPath];
    return contact;
}

@end

NS_ASSUME_NONNULL_END
