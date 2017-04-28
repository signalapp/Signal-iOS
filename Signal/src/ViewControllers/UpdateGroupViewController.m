//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "UpdateGroupViewController.h"
#import "AddToGroupViewController.h"
#import "BlockListUIUtils.h"
#import "ContactAccount.h"
#import "ContactTableViewCell.h"
#import "ContactsViewHelper.h"
#import "Environment.h"
#import "GroupViewHelper.h"
#import "OWSAnyTouchGestureRecognizer.h"
#import "OWSContactsManager.h"
#import "OWSTableViewController.h"
#import "SecurityUtils.h"
#import "SignalKeyingStorage.h"
#import "TSOutgoingMessage.h"
#import "UIUtil.h"
#import "UIView+OWS.h"
#import "UIViewController+OWS.h"
#import <SignalServiceKit/NSDate+millisecondTimeStamp.h>
#import <SignalServiceKit/OWSMessageSender.h>
#import <SignalServiceKit/TSGroupModel.h>
#import <SignalServiceKit/TSGroupThread.h>

NS_ASSUME_NONNULL_BEGIN

@interface UpdateGroupViewController () <UIImagePickerControllerDelegate,
    UITextFieldDelegate,
    ContactsViewHelperDelegate,
    GroupViewHelperDelegate,
    AddToGroupViewControllerDelegate,
    OWSTableViewControllerDelegate,
    UINavigationControllerDelegate>

@property (nonatomic, readonly) OWSMessageSender *messageSender;
@property (nonatomic, readonly) ContactsViewHelper *contactsViewHelper;
@property (nonatomic, readonly) GroupViewHelper *groupViewHelper;

@property (nonatomic, readonly) OWSTableViewController *tableViewController;
@property (nonatomic, readonly) UIImageView *avatarView;
@property (nonatomic, readonly) UITextField *groupNameTextField;

@property (nonatomic, nullable) UIImage *groupAvatar;
@property (nonatomic, nullable) NSSet<NSString *> *previousMemberRecipientIds;
@property (nonatomic, nullable) NSMutableSet<NSString *> *memberRecipientIds;

@property (nonatomic) BOOL hasUnsavedChanges;

@end

#pragma mark -

@implementation UpdateGroupViewController

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
    _messageSender = [Environment getCurrent].messageSender;
    _contactsViewHelper = [ContactsViewHelper new];
    _contactsViewHelper.delegate = self;
    _groupViewHelper = [GroupViewHelper new];
    _groupViewHelper.delegate = self;

    self.memberRecipientIds = [NSMutableSet new];
}

#pragma mark - View Lifecycle

- (void)loadView
{
    [super loadView];

    OWSAssert(self.thread);
    OWSAssert(self.thread.groupModel);
    OWSAssert(self.thread.groupModel.groupMemberIds);

    [self.memberRecipientIds addObjectsFromArray:self.thread.groupModel.groupMemberIds];
    self.previousMemberRecipientIds = [NSSet setWithArray:self.thread.groupModel.groupMemberIds];

    self.title = NSLocalizedString(@"EDIT_GROUP_DEFAULT_TITLE", @"The default title for the 'update group' view.");
    self.navigationItem.leftBarButtonItem =
        [self createOWSBackButtonWithTarget:self selector:@selector(backButtonPressed:)];

    // First section.

    UIView *firstSection = [self firstSectionHeader];
    [self.view addSubview:firstSection];
    [firstSection autoSetDimension:ALDimensionHeight toSize:100.f];
    [firstSection autoPinWidthToSuperview];
    [firstSection autoPinEdgeToSuperviewEdge:ALEdgeTop];

    _tableViewController = [OWSTableViewController new];
    _tableViewController.delegate = self;
    [self.view addSubview:self.tableViewController.view];
    [_tableViewController.view autoPinWidthToSuperview];
    [_tableViewController.view autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:firstSection];
    [_tableViewController.view autoPinEdgeToSuperviewEdge:ALEdgeBottom];

    [self updateTableContents];
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    [self.navigationController.navigationBar setTranslucent:NO];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

    if (self.shouldEditGroupNameOnAppear) {
        [self.groupNameTextField becomeFirstResponder];
    } else if (self.shouldEditAvatarOnAppear) {
        [self showChangeGroupAvatarUI:nil];
    }
    self.shouldEditGroupNameOnAppear = NO;
    self.shouldEditAvatarOnAppear = NO;
}

- (UIView *)firstSectionHeader
{
    UIView *firstSectionHeader = [UIView new];
    firstSectionHeader.backgroundColor = [UIColor whiteColor];
    UIView *threadInfoView = [UIView new];
    [firstSectionHeader addSubview:threadInfoView];
    [threadInfoView autoPinWidthToSuperviewWithMargin:16.f];
    [threadInfoView autoPinHeightToSuperviewWithMargin:16.f];

    const CGFloat kAvatarSize = 68.f;
    UIImageView *avatarView = [UIImageView new];
    _avatarView = avatarView;
    avatarView.layer.borderColor = UIColor.clearColor.CGColor;
    avatarView.layer.masksToBounds = YES;
    avatarView.layer.cornerRadius = kAvatarSize / 2.0f;
    avatarView.contentMode = UIViewContentModeScaleAspectFill;
    [threadInfoView addSubview:avatarView];
    [avatarView autoVCenterInSuperview];
    [avatarView autoPinEdgeToSuperviewEdge:ALEdgeLeft];
    [avatarView autoSetDimension:ALDimensionWidth toSize:kAvatarSize];
    [avatarView autoSetDimension:ALDimensionHeight toSize:kAvatarSize];
    if (self.thread.groupModel) {
        _groupAvatar = self.thread.groupModel.groupImage;
    }
    [self updateAvatarView];

    UITextField *groupNameTextField = [UITextField new];
    _groupNameTextField = groupNameTextField;
    if (self.thread) {
        self.groupNameTextField.text = self.thread.groupModel.groupName;
    }
    groupNameTextField.textColor = [UIColor blackColor];
    groupNameTextField.font = [UIFont ows_dynamicTypeTitle2Font];
    groupNameTextField.placeholder = NSLocalizedString(@"NEW_GROUP_NAMEGROUP_REQUEST_DEFAULT", @"");
    groupNameTextField.delegate = self;
    [groupNameTextField addTarget:self
                           action:@selector(groupNameDidChange:)
                 forControlEvents:UIControlEventEditingChanged];
    [threadInfoView addSubview:groupNameTextField];
    [groupNameTextField autoVCenterInSuperview];
    [groupNameTextField autoPinEdge:ALEdgeLeft toEdge:ALEdgeRight ofView:avatarView withOffset:16.f];
    [groupNameTextField autoPinEdgeToSuperviewEdge:ALEdgeRight withInset:16.f];

    [avatarView addGestureRecognizer:[[OWSAnyTouchGestureRecognizer alloc] initWithTarget:self
                                                                                   action:@selector(avatarTouched:)]];
    avatarView.userInteractionEnabled = YES;

    return firstSectionHeader;
}

- (void)avatarTouched:(UIGestureRecognizer *)sender
{
    if (sender.state == UIGestureRecognizerStateRecognized) {
        [self showChangeGroupAvatarUI:nil];
    }
}

#pragma mark - Table Contents

- (void)updateTableContents
{
    OWSAssert(self.thread);

    OWSTableContents *contents = [OWSTableContents new];

    __weak UpdateGroupViewController *weakSelf = self;
    ContactsViewHelper *helper = self.contactsViewHelper;

    // Group Members

    OWSTableSection *section = [OWSTableSection new];
    section.headerTitle = NSLocalizedString(
        @"EDIT_GROUP_MEMBERS_SECTION_TITLE", @"a title for the members section of the 'new/update group' view.");

    [section addItem:[OWSTableItem itemWithCustomCellBlock:^{
        UITableViewCell *cell = [UITableViewCell new];
        cell.textLabel.text = NSLocalizedString(
            @"EDIT_GROUP_MEMBERS_ADD_MEMBER", @"A label the cell that lets you add a new member to a group.");
        cell.textLabel.font = [UIFont ows_regularFontWithSize:18.f];
        cell.textLabel.textColor = [UIColor blackColor];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
                         customRowHeight:[ContactTableViewCell rowHeight]
                         actionBlock:^{
                             AddToGroupViewController *viewController = [AddToGroupViewController new];
                             viewController.addToGroupDelegate = weakSelf;
                             [weakSelf.navigationController pushViewController:viewController animated:YES];
                         }]];

    NSMutableSet *memberRecipientIds = [self.memberRecipientIds mutableCopy];
    [memberRecipientIds removeObject:[helper localNumber]];
    for (NSString *recipientId in [memberRecipientIds.allObjects sortedArrayUsingSelector:@selector(compare:)]) {
        [section
            addItem:[OWSTableItem itemWithCustomCellBlock:^{
                UpdateGroupViewController *strongSelf = weakSelf;
                if (!strongSelf) {
                    return (ContactTableViewCell *)nil;
                }

                ContactTableViewCell *cell = [ContactTableViewCell new];
                ContactAccount *contactAccount = [helper contactAccountForRecipientId:recipientId];
                BOOL isPreviousMember = [strongSelf.previousMemberRecipientIds containsObject:recipientId];
                BOOL isBlocked = [helper isRecipientIdBlocked:recipientId];
                if (isPreviousMember) {
                    if (isBlocked) {
                        cell.accessoryMessage = NSLocalizedString(
                            @"CONTACT_CELL_IS_BLOCKED", @"An indicator that a contact has been blocked.");
                    } else {
                        cell.selectionStyle = UITableViewCellSeparatorStyleNone;
                    }
                } else {
                    // In the "members" section, we label "new" members as such when editing an existing group.
                    //
                    // The only way a "new" member could be blocked is if we blocked them on a linked device
                    // while in this dialog.  We don't need to worry about that edge case.
                    cell.accessoryMessage = NSLocalizedString(
                        @"EDIT_GROUP_NEW_MEMBER_LABEL", @"An indicator that a user is a new member of the group.");
                }

                if (contactAccount) {
                    // TODO: Use the account label.
                    [cell configureWithContact:contactAccount.contact contactsManager:helper.contactsManager];
                } else {
                    [cell configureWithRecipientId:recipientId contactsManager:helper.contactsManager];
                }

                return cell;
            }
                        customRowHeight:[ContactTableViewCell rowHeight]
                        actionBlock:^{
                            ContactAccount *contactAccount = [helper contactAccountForRecipientId:recipientId];
                            BOOL isPreviousMember = [weakSelf.previousMemberRecipientIds containsObject:recipientId];
                            BOOL isBlocked = [helper isRecipientIdBlocked:recipientId];
                            if (isPreviousMember) {
                                if (isBlocked) {
                                    if (contactAccount) {
                                        [weakSelf showUnblockAlertForContactAccount:contactAccount];
                                    } else {
                                        [weakSelf showUnblockAlertForRecipientId:recipientId];
                                    }
                                }
                            } else {
                                if (contactAccount) {
                                    [weakSelf.groupViewHelper
                                        showRemoveFromGroupAlertForContactAccount:contactAccount
                                                               fromViewController:weakSelf
                                                                  contactsManager:helper.contactsManager
                                                                     successBlock:^{
                                                                         [weakSelf removeContactAccount:contactAccount];
                                                                     }];
                                } else {
                                    [weakSelf.groupViewHelper
                                        showRemoveFromGroupAlertForRecipientId:recipientId
                                                            fromViewController:weakSelf
                                                               contactsManager:helper.contactsManager
                                                                  successBlock:^{
                                                                      [weakSelf removeRecipientId:recipientId];
                                                                  }];
                                }
                            }
                        }]];
    }
    [contents addSection:section];

    self.tableViewController.contents = contents;
}

- (void)showUnblockAlertForContactAccount:(ContactAccount *)contactAccount
{
    OWSAssert(contactAccount);

    __weak UpdateGroupViewController *weakSelf = self;
    ContactsViewHelper *helper = self.contactsViewHelper;
    [BlockListUIUtils showUnblockContactAccountActionSheet:contactAccount
                                        fromViewController:self
                                           blockingManager:helper.blockingManager
                                           contactsManager:helper.contactsManager
                                           completionBlock:^(BOOL isBlocked) {
                                               if (!isBlocked) {
                                                   [weakSelf updateTableContents];
                                               }
                                           }];
}

- (void)showUnblockAlertForRecipientId:(NSString *)recipientId
{
    OWSAssert(recipientId.length > 0);

    __weak UpdateGroupViewController *weakSelf = self;
    ContactsViewHelper *helper = self.contactsViewHelper;
    [BlockListUIUtils showUnblockPhoneNumberActionSheet:recipientId
                                     fromViewController:self
                                        blockingManager:helper.blockingManager
                                        contactsManager:helper.contactsManager
                                        completionBlock:^(BOOL isBlocked) {
                                            if (!isBlocked) {
                                                [weakSelf updateTableContents];
                                            }
                                        }];
}

- (void)removeContactAccount:(ContactAccount *)contactAccount
{
    OWSAssert(contactAccount);

    [self.memberRecipientIds removeObject:contactAccount.recipientId];
    [self updateTableContents];
}

- (void)removeRecipientId:(NSString *)recipientId
{
    OWSAssert(recipientId.length > 0);

    [self.memberRecipientIds removeObject:recipientId];
    [self updateTableContents];
}

#pragma mark - Methods

- (void)updateGroup
{
    OWSAssert(self.delegate);

    TSGroupModel *groupModel = [[TSGroupModel alloc] initWithTitle:self.groupNameTextField.text
                                                         memberIds:[self.memberRecipientIds.allObjects mutableCopy]
                                                             image:self.groupAvatar
                                                           groupId:self.thread.groupModel.groupId];
    [self.delegate groupWasUpdated:groupModel];
}

#pragma mark - Group Avatar

- (void)showChangeGroupAvatarUI:(nullable id)sender
{
    [self.groupNameTextField resignFirstResponder];

    [self.groupViewHelper showChangeGroupAvatarUI];
}

- (void)setGroupAvatar:(nullable UIImage *)groupAvatar
{
    OWSAssert([NSThread isMainThread]);

    _groupAvatar = groupAvatar;

    self.hasUnsavedChanges = YES;

    [self updateAvatarView];
}

- (void)updateAvatarView
{
    UIImage *image = (self.groupAvatar ?: [UIImage imageNamed:@"empty-group-avatar"]);
    OWSAssert(image);

    self.avatarView.image = image;
    self.avatarView.layer.borderColor = [[UIColor lightGrayColor] CGColor];
    self.avatarView.layer.borderWidth = 0.5f;
    self.avatarView.contentMode = UIViewContentModeScaleAspectFill;
}

#pragma mark - Event Handling

- (void)backButtonPressed:(id)sender
{
    [self.groupNameTextField resignFirstResponder];

    if (!self.hasUnsavedChanges) {
        // If user made no changes, return to conversation settings view.
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }

    UIAlertController *controller = [UIAlertController
        alertControllerWithTitle:NSLocalizedString(@"EDIT_GROUP_VIEW_UNSAVED_CHANGES_TITLE",
                                     @"The alert title if user tries to exit update group view without saving changes.")
                         message:
                             NSLocalizedString(@"EDIT_GROUP_VIEW_UNSAVED_CHANGES_MESSAGE",
                                 @"The alert message if user tries to exit update group view without saving changes.")
                  preferredStyle:UIAlertControllerStyleAlert];
    [controller addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"ALERT_SAVE",
                                                             @"The label for the 'save' button in action sheets.")
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction *action) {
                                                     OWSAssert(self.delegate);

                                                     [self updateGroup];

                                                     [self.delegate popAllConversationSettingsViews];
                                                 }]];
    [controller addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"ALERT_DONT_SAVE",
                                                             @"The label for the 'don't save' button in action sheets.")
                                                   style:UIAlertActionStyleDestructive
                                                 handler:^(UIAlertAction *action) {
                                                     [self.navigationController popViewControllerAnimated:YES];
                                                 }]];
    [self presentViewController:controller animated:YES completion:nil];
}


- (void)groupNameDidChange:(id)sender
{
    self.hasUnsavedChanges = YES;
}

#pragma mark - Text Field Delegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    [self.groupNameTextField resignFirstResponder];
    return NO;
}

#pragma mark - OWSTableViewControllerDelegate

- (void)tableViewDidScroll
{
    [self.groupNameTextField resignFirstResponder];
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

#pragma mark - GroupViewHelperDelegate

- (void)groupAvatarDidChange:(UIImage *)image
{
    OWSAssert(image);

    self.groupAvatar = image;
}

- (UIViewController *)fromViewController
{
    return self;
}

#pragma mark - AddToGroupViewControllerDelegate

- (void)recipientIdWasAdded:(NSString *)recipientId
{
    [self.memberRecipientIds addObject:recipientId];
    self.hasUnsavedChanges = YES;
    [self updateTableContents];
}

@end

NS_ASSUME_NONNULL_END
