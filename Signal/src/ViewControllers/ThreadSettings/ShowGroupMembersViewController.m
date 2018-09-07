//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "ShowGroupMembersViewController.h"
#import "Signal-Swift.h"
#import "SignalApp.h"
#import "ViewControllerUtils.h"
#import <SignalMessaging/BlockListUIUtils.h>
#import <SignalMessaging/ContactTableViewCell.h>
#import <SignalMessaging/ContactsViewHelper.h>
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/OWSContactsManager.h>
#import <SignalMessaging/UIUtil.h>
#import <SignalServiceKit/OWSBlockingManager.h>
#import <SignalServiceKit/SignalAccount.h>
#import <SignalServiceKit/TSGroupModel.h>
#import <SignalServiceKit/TSGroupThread.h>

@import ContactsUI;

NS_ASSUME_NONNULL_BEGIN

@interface ShowGroupMembersViewController () <ContactsViewHelperDelegate, ContactEditingDelegate>

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
    _contactsViewHelper = [[ContactsViewHelper alloc] initWithDelegate:self];

    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 60;

    [self observeNotifications];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)observeNotifications
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(identityStateDidChange:)
                                                 name:kNSNotificationName_IdentityStateDidChange
                                               object:nil];
}

- (void)configWithThread:(TSGroupThread *)thread
{

    _thread = thread;

    OWSAssertDebug(self.thread);
    OWSAssertDebug(self.thread.groupModel);
    OWSAssertDebug(self.thread.groupModel.groupMemberIds);

    self.memberRecipientIds = [NSSet setWithArray:self.thread.groupModel.groupMemberIds];
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    OWSAssertDebug([self.navigationController isKindOfClass:[OWSNavigationController class]]);

    self.title = _thread.groupModel.groupName;

    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 45;

    [self updateTableContents];
}

#pragma mark - Table Contents

- (void)updateTableContents
{
    OWSAssertDebug(self.thread);

    OWSTableContents *contents = [OWSTableContents new];

    __weak ShowGroupMembersViewController *weakSelf = self;
    ContactsViewHelper *helper = self.contactsViewHelper;

    OWSTableSection *membersSection = [OWSTableSection new];

    // Group Members

    // If there are "no longer verified" members of the group,
    // highlight them in a special section.
    NSArray<NSString *> *noLongerVerifiedRecipientIds = [self noLongerVerifiedRecipientIds];
    if (noLongerVerifiedRecipientIds.count > 0) {
        OWSTableSection *noLongerVerifiedSection = [OWSTableSection new];
        noLongerVerifiedSection.headerTitle = NSLocalizedString(@"GROUP_MEMBERS_SECTION_TITLE_NO_LONGER_VERIFIED",
            @"Title for the 'no longer verified' section of the 'group members' view.");
        membersSection.headerTitle = NSLocalizedString(
            @"GROUP_MEMBERS_SECTION_TITLE_MEMBERS", @"Title for the 'members' section of the 'group members' view.");
        [noLongerVerifiedSection
            addItem:[OWSTableItem disclosureItemWithText:NSLocalizedString(@"GROUP_MEMBERS_RESET_NO_LONGER_VERIFIED",
                                                             @"Label for the button that clears all verification "
                                                             @"errors in the 'group members' view.")
                                         customRowHeight:UITableViewAutomaticDimension
                                             actionBlock:^{
                                                 [weakSelf offerResetAllNoLongerVerified];
                                             }]];
        [self addMembers:noLongerVerifiedRecipientIds toSection:noLongerVerifiedSection useVerifyAction:YES];
        [contents addSection:noLongerVerifiedSection];
    }

    NSMutableSet *memberRecipientIds = [self.memberRecipientIds mutableCopy];
    [memberRecipientIds removeObject:[helper localNumber]];
    [self addMembers:memberRecipientIds.allObjects toSection:membersSection useVerifyAction:NO];
    [contents addSection:membersSection];

    self.contents = contents;
}

- (void)addMembers:(NSArray<NSString *> *)recipientIds
          toSection:(OWSTableSection *)section
    useVerifyAction:(BOOL)useVerifyAction
{
    OWSAssertDebug(recipientIds);
    OWSAssertDebug(section);

    __weak ShowGroupMembersViewController *weakSelf = self;
    ContactsViewHelper *helper = self.contactsViewHelper;
    // Sort the group members using contacts manager.
    NSArray<NSString *> *sortedRecipientIds = [recipientIds sortedArrayUsingComparator:^NSComparisonResult(
        NSString *recipientIdA, NSString *recipientIdB) {
        SignalAccount *signalAccountA = [helper.contactsManager fetchOrBuildSignalAccountForRecipientId:recipientIdA];
        SignalAccount *signalAccountB = [helper.contactsManager fetchOrBuildSignalAccountForRecipientId:recipientIdB];
        return [helper.contactsManager compareSignalAccount:signalAccountA withSignalAccount:signalAccountB];
    }];
    for (NSString *recipientId in sortedRecipientIds) {
        [section addItem:[OWSTableItem
                             itemWithCustomCellBlock:^{
                                 ShowGroupMembersViewController *strongSelf = weakSelf;
                                 OWSCAssertDebug(strongSelf);

                                 ContactTableViewCell *cell = [ContactTableViewCell new];
                                 OWSVerificationState verificationState =
                                     [[OWSIdentityManager sharedManager] verificationStateForRecipientId:recipientId];
                                 BOOL isVerified = verificationState == OWSVerificationStateVerified;
                                 BOOL isNoLongerVerified = verificationState == OWSVerificationStateNoLongerVerified;
                                 BOOL isBlocked = [helper isRecipientIdBlocked:recipientId];
                                 if (isNoLongerVerified) {
                                     cell.accessoryMessage = NSLocalizedString(@"CONTACT_CELL_IS_NO_LONGER_VERIFIED",
                                         @"An indicator that a contact is no longer verified.");
                                 } else if (isBlocked) {
                                     cell.accessoryMessage = NSLocalizedString(
                                         @"CONTACT_CELL_IS_BLOCKED", @"An indicator that a contact has been blocked.");
                                 }

                                 [cell configureWithRecipientId:recipientId contactsManager:helper.contactsManager];

                                 if (isVerified) {
                                     [cell setAttributedSubtitle:cell.verifiedSubtitle];
                                 } else {
                                     [cell setAttributedSubtitle:nil];
                                 }

                                 return cell;
                             }
                             customRowHeight:UITableViewAutomaticDimension
                             actionBlock:^{
                                 if (useVerifyAction) {
                                     [weakSelf showSafetyNumberView:recipientId];
                                 } else {
                                     [weakSelf didSelectRecipientId:recipientId];
                                 }
                             }]];
    }
}

- (void)offerResetAllNoLongerVerified
{
    OWSAssertIsOnMainThread();

    UIAlertController *actionSheetController = [UIAlertController
        alertControllerWithTitle:nil
                         message:NSLocalizedString(@"GROUP_MEMBERS_RESET_NO_LONGER_VERIFIED_ALERT_MESSAGE",
                                     @"Label for the 'reset all no-longer-verified group members' confirmation alert.")
                  preferredStyle:UIAlertControllerStyleAlert];

    __weak ShowGroupMembersViewController *weakSelf = self;
    UIAlertAction *verifyAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil)
                                                           style:UIAlertActionStyleDestructive
                                                         handler:^(UIAlertAction *_Nonnull action) {
                                                             [weakSelf resetAllNoLongerVerified];
                                                         }];
    [actionSheetController addAction:verifyAction];
    [actionSheetController addAction:[OWSAlerts cancelAction]];

    [self presentViewController:actionSheetController animated:YES completion:nil];
}

- (void)resetAllNoLongerVerified
{
    OWSAssertIsOnMainThread();

    OWSIdentityManager *identityManger = [OWSIdentityManager sharedManager];
    NSArray<NSString *> *recipientIds = [self noLongerVerifiedRecipientIds];
    for (NSString *recipientId in recipientIds) {
        OWSVerificationState verificationState = [identityManger verificationStateForRecipientId:recipientId];
        if (verificationState == OWSVerificationStateNoLongerVerified) {
            NSData *identityKey = [identityManger identityKeyForRecipientId:recipientId];
            if (identityKey.length < 1) {
                OWSFailDebug(@"Missing identity key for: %@", recipientId);
                continue;
            }
            [identityManger setVerificationState:OWSVerificationStateDefault
                                     identityKey:identityKey
                                     recipientId:recipientId
                           isUserInitiatedChange:YES];
        }
    }

    [self updateTableContents];
}

// Returns a collection of the group members who are "no longer verified".
- (NSArray<NSString *> *)noLongerVerifiedRecipientIds
{
    NSMutableArray<NSString *> *result = [NSMutableArray new];
    for (NSString *recipientId in self.thread.recipientIdentifiers) {
        if ([[OWSIdentityManager sharedManager] verificationStateForRecipientId:recipientId]
            == OWSVerificationStateNoLongerVerified) {
            [result addObject:recipientId];
        }
    }
    return [result copy];
}

- (void)didSelectRecipientId:(NSString *)recipientId
{
    OWSAssertDebug(recipientId.length > 0);

    ContactsViewHelper *helper = self.contactsViewHelper;
    SignalAccount *_Nullable signalAccount = [helper fetchSignalAccountForRecipientId:recipientId];

    UIAlertController *actionSheetController =
        [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];

    if (self.contactsViewHelper.contactsManager.supportsContactEditing) {
        NSString *contactInfoTitle = signalAccount
            ? NSLocalizedString(@"GROUP_MEMBERS_VIEW_CONTACT_INFO", @"Button label for the 'show contact info' button")
            : NSLocalizedString(
                  @"GROUP_MEMBERS_ADD_CONTACT_INFO", @"Button label to add information to an unknown contact");
        [actionSheetController addAction:[UIAlertAction actionWithTitle:contactInfoTitle
                                                                  style:UIAlertActionStyleDefault
                                                                handler:^(UIAlertAction *_Nonnull action) {
                                                                    [self
                                                                        showContactInfoViewForRecipientId:recipientId];
                                                                }]];
    }

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
                                                                             completionBlock:^(BOOL ignore) {
                                                                                 [self updateTableContents];
                                                                             }];
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
                                                                           completionBlock:^(BOOL ignore) {
                                                                               [self updateTableContents];
                                                                           }];
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
                                                                           completionBlock:^(BOOL ignore) {
                                                                               [self updateTableContents];
                                                                           }];
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
                                                                         completionBlock:^(BOOL ignore) {
                                                                             [self updateTableContents];
                                                                         }];
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
        [actionSheetController
            addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"VERIFY_PRIVACY",
                                                         @"Label for button or row which allows users to verify the "
                                                         @"safety number of another user.")
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *_Nonnull action) {
                                                 [self showSafetyNumberView:recipientId];
                                             }]];
    }

    [actionSheetController addAction:[OWSAlerts cancelAction]];

    [self presentViewController:actionSheetController animated:YES completion:nil];
}

- (void)showContactInfoViewForRecipientId:(NSString *)recipientId
{
    OWSAssertDebug(recipientId.length > 0);

    [self.contactsViewHelper presentContactViewControllerForRecipientId:recipientId
                                                     fromViewController:self
                                                        editImmediately:NO];
}

- (void)showConversationViewForRecipientId:(NSString *)recipientId
{
    OWSAssertDebug(recipientId.length > 0);

    [SignalApp.sharedApp presentConversationForRecipientId:recipientId
                                                    action:ConversationViewActionCompose
                                                  animated:YES];
}

- (void)callMember:(NSString *)recipientId
{
    [SignalApp.sharedApp presentConversationForRecipientId:recipientId
                                                    action:ConversationViewActionAudioCall
                                                  animated:YES];
}

- (void)showSafetyNumberView:(NSString *)recipientId
{
    OWSAssertDebug(recipientId.length > 0);

    [FingerprintViewController presentFromViewController:self recipientId:recipientId];
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

#pragma mark - ContactEditingDelegate

- (void)didFinishEditingContact
{
    OWSLogDebug(@"");
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - CNContactViewControllerDelegate

- (void)contactViewController:(CNContactViewController *)viewController
       didCompleteWithContact:(nullable CNContact *)contact
{
    OWSLogDebug(@"done editing contact.");
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Notifications

- (void)identityStateDidChange:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    [self updateTableContents];
}

@end

NS_ASSUME_NONNULL_END
