//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "NewGroupViewController.h"
#import "AddToGroupViewController.h"
#import "BlockListUIUtils.h"
#import "ContactTableViewCell.h"
#import "ContactsViewHelper.h"
#import "Environment.h"
#import "GroupViewHelper.h"
#import "OWSContactsManager.h"
#import "OWSTableViewController.h"
#import "SecurityUtils.h"
#import "Signal-Swift.h"
#import "SignalKeyingStorage.h"
#import "TSOutgoingMessage.h"
#import "UIUtil.h"
#import "UIView+OWS.h"
#import "UIViewController+OWS.h"
#import <SignalServiceKit/NSDate+millisecondTimeStamp.h>
#import <SignalServiceKit/OWSMessageSender.h>
#import <SignalServiceKit/SignalAccount.h>
#import <SignalServiceKit/TSGroupModel.h>
#import <SignalServiceKit/TSGroupThread.h>

NS_ASSUME_NONNULL_BEGIN

@interface NewGroupViewController () <UIImagePickerControllerDelegate,
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
@property (nonatomic) NSMutableSet<NSString *> *memberRecipientIds;

@property (nonatomic) BOOL hasUnsavedChanges;
@property (nonatomic) BOOL hasAppeared;

@end

#pragma mark -

@implementation NewGroupViewController

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

    self.title = NSLocalizedString(@"NEW_GROUP_DEFAULT_TITLE", @"The navbar title for the 'new group' view.");
    self.navigationItem.leftBarButtonItem =
        [self createOWSBackButtonWithTarget:self selector:@selector(backButtonPressed:)];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:NSLocalizedString(@"NEW_GROUP_CREATE_BUTTON", @"The title for the 'create group' button.")
                style:UIBarButtonItemStylePlain
               target:self
               action:@selector(createGroup)];
    self.navigationItem.rightBarButtonItem.imageInsets = UIEdgeInsetsMake(0, -10, 0, 10);
    self.navigationItem.rightBarButtonItem.accessibilityLabel
        = NSLocalizedString(@"FINISH_GROUP_CREATION_LABEL", @"Accessibilty label for finishing new group");

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
    [self updateAvatarView];

    UITextField *groupNameTextField = [UITextField new];
    _groupNameTextField = groupNameTextField;
    groupNameTextField.textColor = [UIColor blackColor];
    groupNameTextField.font = [UIFont ows_dynamicTypeTitle2Font];
    groupNameTextField.placeholder
        = NSLocalizedString(@"NEW_GROUP_NAMEGROUP_REQUEST_DEFAULT", @"Placeholder text for group name field");
    groupNameTextField.delegate = self;
    [groupNameTextField addTarget:self
                           action:@selector(groupNameDidChange:)
                 forControlEvents:UIControlEventEditingChanged];
    [threadInfoView addSubview:groupNameTextField];
    [groupNameTextField autoVCenterInSuperview];
    [groupNameTextField autoPinEdge:ALEdgeLeft toEdge:ALEdgeRight ofView:avatarView withOffset:16.f];
    [groupNameTextField autoPinEdgeToSuperviewEdge:ALEdgeRight withInset:16.f];

    [avatarView
        addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(avatarTouched:)]];
    avatarView.userInteractionEnabled = YES;

    return firstSectionHeader;
}

- (void)avatarTouched:(UIGestureRecognizer *)sender
{
    if (sender.state == UIGestureRecognizerStateRecognized) {
        [self showChangeGroupAvatarUI];
    }
}

#pragma mark - Table Contents

- (void)updateTableContents
{
    OWSTableContents *contents = [OWSTableContents new];

    __weak NewGroupViewController *weakSelf = self;
    ContactsViewHelper *contactsViewHelper = self.contactsViewHelper;

    NSArray<SignalAccount *> *signalAccounts = self.contactsViewHelper.signalAccounts;
    NSMutableSet *nonContactMemberRecipientIds = [self.memberRecipientIds mutableCopy];
    for (SignalAccount *signalAccount in signalAccounts) {
        [nonContactMemberRecipientIds removeObject:signalAccount.recipientId];
    }

    // Non-contact Members

    if (nonContactMemberRecipientIds.count > 0 || signalAccounts.count < 1) {

        OWSTableSection *nonContactsSection = [OWSTableSection new];
        nonContactsSection.headerTitle = NSLocalizedString(
            @"NEW_GROUP_NON_CONTACTS_SECTION_TITLE", @"a title for the non-contacts section of the 'new group' view.");

        [nonContactsSection addItem:[self createAddNonContactItem]];

        for (NSString *recipientId in
            [nonContactMemberRecipientIds.allObjects sortedArrayUsingSelector:@selector(compare:)]) {

            [nonContactsSection
                addItem:[OWSTableItem itemWithCustomCellBlock:^{
                    NewGroupViewController *strongSelf = weakSelf;
                    OWSAssert(strongSelf);

                    ContactTableViewCell *cell = [ContactTableViewCell new];
                    SignalAccount *signalAccount = [contactsViewHelper signalAccountForRecipientId:recipientId];
                    BOOL isCurrentMember = [strongSelf.memberRecipientIds containsObject:recipientId];
                    BOOL isBlocked = [contactsViewHelper isRecipientIdBlocked:recipientId];
                    if (isCurrentMember) {
                        // In the "contacts" section, we label members as such when editing an existing group.
                        cell.accessoryMessage = NSLocalizedString(
                            @"NEW_GROUP_MEMBER_LABEL", @"An indicator that a user is a member of the new group.");
                    } else if (isBlocked) {
                        cell.accessoryMessage = NSLocalizedString(
                            @"CONTACT_CELL_IS_BLOCKED", @"An indicator that a contact has been blocked.");
                    } else {
                        OWSAssert(cell.accessoryMessage == nil);
                    }

                    if (signalAccount) {
                        [cell configureWithSignalAccount:signalAccount
                                         contactsManager:contactsViewHelper.contactsManager];
                    } else {
                        [cell configureWithRecipientId:recipientId contactsManager:contactsViewHelper.contactsManager];
                    }

                    return cell;
                }
                            customRowHeight:[ContactTableViewCell rowHeight]
                            actionBlock:^{
                                BOOL isCurrentMember = [weakSelf.memberRecipientIds containsObject:recipientId];
                                BOOL isBlocked = [contactsViewHelper isRecipientIdBlocked:recipientId];
                                if (isCurrentMember) {
                                    [weakSelf removeRecipientId:recipientId];
                                } else if (isBlocked) {
                                    [BlockListUIUtils
                                        showUnblockPhoneNumberActionSheet:recipientId
                                                       fromViewController:weakSelf
                                                          blockingManager:contactsViewHelper.blockingManager
                                                          contactsManager:contactsViewHelper.contactsManager
                                                          completionBlock:^(BOOL isStillBlocked) {
                                                              if (!isStillBlocked) {
                                                                  [weakSelf addRecipientId:recipientId];
                                                              }
                                                          }];
                                } else {
                                    [weakSelf addRecipientId:recipientId];
                                }
                            }]];
        }
        [contents addSection:nonContactsSection];
    }

    // Contacts

    OWSTableSection *signalAccountSection = [OWSTableSection new];
    signalAccountSection.headerTitle = NSLocalizedString(
        @"EDIT_GROUP_CONTACTS_SECTION_TITLE", @"a title for the contacts section of the 'new/update group' view.");
    if (signalAccounts.count > 0) {

        if (nonContactMemberRecipientIds.count < 1) {
            // If the group contains any non-contacts or has not contacts,
            // the "add non-contact user" will show up in the previous section
            // of the table. However, it's more attractive to hide that section
            // for the common case where people want to create a group from just
            // their contacts.  Therefore, when that section is hidden, we want
            // to allow people to add non-contacts.
            [signalAccountSection addItem:[self createAddNonContactItem]];
        }

        for (SignalAccount *signalAccount in signalAccounts) {
            [signalAccountSection
                addItem:[OWSTableItem itemWithCustomCellBlock:^{
                    NewGroupViewController *strongSelf = weakSelf;
                    OWSAssert(strongSelf);

                    ContactTableViewCell *cell = [ContactTableViewCell new];

                    NSString *recipientId = signalAccount.recipientId;
                    BOOL isCurrentMember = [strongSelf.memberRecipientIds containsObject:recipientId];
                    BOOL isBlocked = [contactsViewHelper isRecipientIdBlocked:recipientId];
                    if (isCurrentMember) {
                        // In the "contacts" section, we label members as such when editing an existing group.
                        cell.accessoryMessage = NSLocalizedString(
                            @"NEW_GROUP_MEMBER_LABEL", @"An indicator that a user is a member of the new group.");
                    } else if (isBlocked) {
                        cell.accessoryMessage = NSLocalizedString(
                            @"CONTACT_CELL_IS_BLOCKED", @"An indicator that a contact has been blocked.");
                    } else {
                        OWSAssert(cell.accessoryMessage == nil);
                    }

                    [cell configureWithSignalAccount:signalAccount contactsManager:contactsViewHelper.contactsManager];

                    return cell;
                }
                            customRowHeight:[ContactTableViewCell rowHeight]
                            actionBlock:^{
                                NSString *recipientId = signalAccount.recipientId;
                                BOOL isCurrentMember = [weakSelf.memberRecipientIds containsObject:recipientId];
                                BOOL isBlocked = [contactsViewHelper isRecipientIdBlocked:recipientId];
                                if (isCurrentMember) {
                                    [weakSelf removeRecipientId:recipientId];
                                } else if (isBlocked) {
                                    [BlockListUIUtils
                                        showUnblockSignalAccountActionSheet:signalAccount
                                                         fromViewController:weakSelf
                                                            blockingManager:contactsViewHelper.blockingManager
                                                            contactsManager:contactsViewHelper.contactsManager
                                                            completionBlock:^(BOOL isStillBlocked) {
                                                                if (!isStillBlocked) {
                                                                    [weakSelf addRecipientId:recipientId];
                                                                }
                                                            }];
                                } else {
                                    [weakSelf addRecipientId:recipientId];
                                }
                            }]];
        }
    } else {
        [signalAccountSection addItem:[OWSTableItem itemWithCustomCellBlock:^{
            UITableViewCell *cell = [UITableViewCell new];
            cell.textLabel.text = NSLocalizedString(
                @"SETTINGS_BLOCK_LIST_NO_CONTACTS", @"A label that indicates the user has no Signal contacts.");
            cell.textLabel.font = [UIFont ows_regularFontWithSize:15.f];
            cell.textLabel.textColor = [UIColor colorWithWhite:0.5f alpha:1.f];
            cell.textLabel.textAlignment = NSTextAlignmentCenter;
            return cell;
        }
                                                                actionBlock:nil]];
    }
    [contents addSection:signalAccountSection];

    self.tableViewController.contents = contents;
}

- (OWSTableItem *)createAddNonContactItem
{
    __weak NewGroupViewController *weakSelf = self;
    return [OWSTableItem itemWithCustomCellBlock:^{
        UITableViewCell *cell = [UITableViewCell new];
        cell.textLabel.text = NSLocalizedString(@"NEW_GROUP_ADD_NON_CONTACT",
            @"A label for the cell that lets you add a new non-contact member to a group.");
        cell.textLabel.font = [UIFont ows_regularFontWithSize:18.f];
        cell.textLabel.textColor = [UIColor blackColor];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
        customRowHeight:[ContactTableViewCell rowHeight]
        actionBlock:^{
            AddToGroupViewController *viewController = [AddToGroupViewController new];
            viewController.addToGroupDelegate = weakSelf;
            viewController.hideContacts = YES;
            [weakSelf.navigationController pushViewController:viewController animated:YES];
        }];
}

- (void)removeRecipientId:(NSString *)recipientId
{
    OWSAssert(recipientId.length > 0);

    [self.memberRecipientIds removeObject:recipientId];
    [self updateTableContents];
}

- (void)addRecipientId:(NSString *)recipientId
{
    OWSAssert(recipientId.length > 0);

    [self.memberRecipientIds addObject:recipientId];
    self.hasUnsavedChanges = YES;
    [self updateTableContents];
}

#pragma mark - Methods

- (void)viewDidLoad
{
    [super viewDidLoad];

    [self.navigationController.navigationBar setTranslucent:NO];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

    if (!self.hasAppeared) {
        [self.groupNameTextField becomeFirstResponder];
        self.hasAppeared = YES;
    }
}

#pragma mark - Actions

- (void)createGroup
{
    TSGroupModel *model = [self makeGroup];

    __block TSGroupThread *thread;
    [[TSStorageManager sharedManager].dbConnection
        readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
            thread = [TSGroupThread getOrCreateThreadWithGroupModel:model transaction:transaction];
        }];
    OWSAssert(thread);

    void (^popToThread)() = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [self dismissViewControllerAnimated:YES
                                     completion:^{
                                         [Environment messageGroup:thread];
                                     }];

        });
    };

    void (^removeThreadWithError)(NSError *error) = ^(NSError *error) {
        [thread remove];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self dismissViewControllerAnimated:YES
                                     completion:^{
                                         [OWSAlerts
                                             showAlertWithTitle:
                                                 NSLocalizedString(@"GROUP_CREATING_FAILED",
                                                     "Title of alert indicating that new group could not be created.")
                                                        message:error.localizedDescription];
                                     }];
        });
    };

    UIAlertController *alertController =
        [UIAlertController alertControllerWithTitle:NSLocalizedString(@"GROUP_CREATING", nil)
                                            message:nil
                                     preferredStyle:UIAlertControllerStyleAlert];

    [self presentViewController:alertController
                       animated:YES
                     completion:^{
                         TSOutgoingMessage *message =
                             [[TSOutgoingMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                                 inThread:thread
                                                         groupMetaMessage:TSGroupMessageNew];

                         // This will save the message.
                         [message updateWithCustomMessage:NSLocalizedString(@"GROUP_CREATED", nil)];
                         if (model.groupImage) {
                             [self.messageSender sendAttachmentData:UIImagePNGRepresentation(model.groupImage)
                                                        contentType:OWSMimeTypeImagePng
                                                           filename:nil
                                                          inMessage:message
                                                            success:popToThread
                                                            failure:removeThreadWithError];
                         } else {
                             [self.messageSender sendMessage:message success:popToThread failure:removeThreadWithError];
                         }
                     }];
}

- (TSGroupModel *)makeGroup
{
    NSString *title = self.groupNameTextField.text;
    NSMutableArray<NSString *> *recipientIds = [self.memberRecipientIds.allObjects mutableCopy];
    [recipientIds addObject:[self.contactsViewHelper localNumber]];
    NSData *groupId = [SecurityUtils generateRandomBytes:16];

    return [[TSGroupModel alloc] initWithTitle:title memberIds:recipientIds image:self.groupAvatar groupId:groupId];
}

#pragma mark - Group Avatar

- (void)showChangeGroupAvatarUI
{
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
        alertControllerWithTitle:
            NSLocalizedString(@"NEW_GROUP_VIEW_UNSAVED_CHANGES_TITLE",
                @"The alert title if user tries to exit the new group view without saving changes.")
                         message:
                             NSLocalizedString(@"NEW_GROUP_VIEW_UNSAVED_CHANGES_MESSAGE",
                                 @"The alert message if user tries to exit the new group view without saving changes.")
                  preferredStyle:UIAlertControllerStyleAlert];
    [controller
        addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"ALERT_DISCARD_BUTTON",
                                                     @"The label for the 'discard' button in alerts and action sheets.")
                                           style:UIAlertActionStyleDestructive
                                         handler:^(UIAlertAction *action) {
                                             [self.navigationController popViewControllerAnimated:YES];
                                         }]];
    [controller addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"TXT_CANCEL_TITLE", nil)
                                                   style:UIAlertActionStyleCancel
                                                 handler:nil]];
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
    [self addRecipientId:recipientId];
}

- (BOOL)isRecipientGroupMember:(NSString *)recipientId
{
    OWSAssert(recipientId.length > 0);

    return [self.memberRecipientIds containsObject:recipientId];
}

@end

NS_ASSUME_NONNULL_END
