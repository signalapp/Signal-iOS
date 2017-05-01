//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "ShowGroupMembersViewController.h"
#import "BlockListUIUtils.h"
#import "ContactTableViewCell.h"
#import "ContactsViewHelper.h"
#import "Environment.h"
#import "OWSContactsManager.h"
#import "SignalAccount.h"
#import "SignalsViewController.h"
#import "UIUtil.h"
#import <AddressBookUI/AddressBookUI.h>
#import <SignalServiceKit/OWSBlockingManager.h>
#import <SignalServiceKit/TSGroupModel.h>
#import <SignalServiceKit/TSGroupThread.h>

NS_ASSUME_NONNULL_BEGIN

@interface ShowGroupMembersViewController () <ContactsViewHelperDelegate>

@property (nonatomic, readonly) TSGroupThread *thread;
@property (nonatomic, readonly) ContactsViewHelper *contactsViewHelper;

@property (nonatomic, nullable) NSSet<NSString *> *memberRecipientIds;

@end

#pragma mark -

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
    _contactsViewHelper = [ContactsViewHelper new];
    _contactsViewHelper.delegate = self;
}

- (void)configWithThread:(TSGroupThread *)thread
{

    _thread = thread;

    OWSAssert(self.thread);
    OWSAssert(self.thread.groupModel);
    OWSAssert(self.thread.groupModel.groupMemberIds);

    self.memberRecipientIds = [NSSet setWithArray:self.thread.groupModel.groupMemberIds];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.navigationController.navigationBar setTranslucent:NO];

    self.title = _thread.groupModel.groupName;

    [self updateTableContents];
}

#pragma mark - Table Contents

- (void)updateTableContents
{
    OWSAssert(self.thread);

    OWSTableContents *contents = [OWSTableContents new];

    __weak ShowGroupMembersViewController *weakSelf = self;
    ContactsViewHelper *helper = self.contactsViewHelper;

    // Group Members

    OWSTableSection *section = [OWSTableSection new];

    NSMutableSet *memberRecipientIds = [self.memberRecipientIds mutableCopy];
    [memberRecipientIds removeObject:[helper localNumber]];
    for (NSString *recipientId in [memberRecipientIds.allObjects sortedArrayUsingSelector:@selector(compare:)]) {
        [section addItem:[OWSTableItem itemWithCustomCellBlock:^{
            ShowGroupMembersViewController *strongSelf = weakSelf;
            if (!strongSelf) {
                return (ContactTableViewCell *)nil;
            }

            ContactTableViewCell *cell = [ContactTableViewCell new];
            SignalAccount *signalAccount = [helper signalAccountForRecipientId:recipientId];
            BOOL isBlocked = [helper isRecipientIdBlocked:recipientId];
            if (isBlocked) {
                cell.accessoryMessage
                    = NSLocalizedString(@"CONTACT_CELL_IS_BLOCKED", @"An indicator that a contact has been blocked.");
            }

            if (signalAccount) {
                [cell configureWithSignalAccount:signalAccount contactsManager:helper.contactsManager];
            } else {
                [cell configureWithRecipientId:recipientId contactsManager:helper.contactsManager];
            }

            return cell;
        }
                             customRowHeight:[ContactTableViewCell rowHeight]
                             actionBlock:^{
                                 [weakSelf didSelectRecipientId:recipientId];
                             }]];
    }
    [contents addSection:section];

    self.contents = contents;
}

- (void)didSelectRecipientId:(NSString *)recipientId
{
    OWSAssert(recipientId.length > 0);

    ContactsViewHelper *helper = self.contactsViewHelper;
    SignalAccount *signalAccount = [helper signalAccountForRecipientId:recipientId];

    UIAlertController *actionSheetController =
        [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];

    [actionSheetController
        addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"GROUP_MEMBERS_VIEW_CONTACT_INFO",
                                                     @"Button label for the 'show contact info' button")
                                           style:UIAlertActionStyleDefault
                                         handler:^(UIAlertAction *_Nonnull action) {
                                             [self showContactInfoViewForRecipientId:recipientId];
                                         }]];

    BOOL isBlocked;
    if (signalAccount) {
        isBlocked = [helper isRecipientIdBlocked:signalAccount.recipientId];
        if (isBlocked) {
            [actionSheetController
                addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"BLOCK_LIST_UNBLOCK_BUTTON",
                                                             @"Button label for the 'unblock' button")
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction *_Nonnull action) {
                                                     [BlockListUIUtils
                                                         showUnblockSignalAccountActionSheet:signalAccount
                                                                          fromViewController:self
                                                                             blockingManager:helper.blockingManager
                                                                             contactsManager:helper.contactsManager
                                                                             completionBlock:nil];
                                                 }]];
        } else {
            [actionSheetController
                addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"BLOCK_LIST_BLOCK_BUTTON",
                                                             @"Button label for the 'block' button")
                                                   style:UIAlertActionStyleDestructive
                                                 handler:^(UIAlertAction *_Nonnull action) {
                                                     [BlockListUIUtils
                                                         showBlockSignalAccountActionSheet:signalAccount
                                                                        fromViewController:self
                                                                           blockingManager:helper.blockingManager
                                                                           contactsManager:helper.contactsManager
                                                                           completionBlock:nil];
                                                 }]];
        }
    } else {
        isBlocked = [helper isRecipientIdBlocked:recipientId];
        if (isBlocked) {
            [actionSheetController
                addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"BLOCK_LIST_UNBLOCK_BUTTON",
                                                             @"Button label for the 'unblock' button")
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction *_Nonnull action) {
                                                     [BlockListUIUtils
                                                         showUnblockPhoneNumberActionSheet:recipientId
                                                                        fromViewController:self
                                                                           blockingManager:helper.blockingManager
                                                                           contactsManager:helper.contactsManager
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
                                                                         blockingManager:helper.blockingManager
                                                                         contactsManager:helper.contactsManager
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
                                                 [self showConversationViewForRecipientId:recipientId];
                                             }]];
        [actionSheetController
            addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"GROUP_MEMBERS_CALL",
                                                         @"Button label for the 'call group member' button")
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *_Nonnull action) {
                                                 [self callMember:recipientId];
                                             }]];
    }

    UIAlertAction *dismissAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"TXT_CANCEL_TITLE", @"")
                                                            style:UIAlertActionStyleCancel
                                                          handler:nil];
    [actionSheetController addAction:dismissAction];

    [self presentViewController:actionSheetController animated:YES completion:nil];
}

- (void)showContactInfoViewForRecipientId:(NSString *)recipientId
{
    OWSAssert(recipientId.length > 0);

    ContactsViewHelper *helper = self.contactsViewHelper;
    SignalAccount *signalAccount = [helper signalAccountForRecipientId:recipientId];

    if (signalAccount) {
        ABPersonViewController *view = [[ABPersonViewController alloc] init];

        ABAddressBookRef addressBookRef = ABAddressBookCreateWithOptions(NULL, nil);
        // Assume person is already defined.
        view.displayedPerson = ABAddressBookGetPersonWithRecordID(addressBookRef, signalAccount.contact.recordID);
        view.allowsActions = NO;
        view.allowsEditing = YES;

        [self.navigationController pushViewController:view animated:YES];
    } else {
        ABUnknownPersonViewController *view = [[ABUnknownPersonViewController alloc] init];

        ABRecordRef aContact = ABPersonCreate();
        CFErrorRef anError   = NULL;

        ABMultiValueRef phone = ABMultiValueCreateMutable(kABMultiStringPropertyType);
        ABMultiValueAddValueAndLabel(phone, (__bridge CFTypeRef)recipientId, kABPersonPhoneMainLabel, NULL);

        ABRecordSetValue(aContact, kABPersonPhoneProperty, phone, &anError);
        CFRelease(phone);

        if (!anError && aContact) {
            view.displayedPerson = aContact; // Assume person is already defined.
            view.allowsAddingToAddressBook = YES;
            [self.navigationController pushViewController:view animated:YES];
        }
    }
}

- (void)showConversationViewForRecipientId:(NSString *)recipientId
{
    OWSAssert(recipientId.length > 0);

    [Environment messageIdentifier:recipientId withCompose:YES];
}

- (void)callMember:(NSString *)recipientId
{
    [Environment callUserWithIdentifier:recipientId];
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

@end

NS_ASSUME_NONNULL_END
