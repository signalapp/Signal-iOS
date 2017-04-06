//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "NewGroupViewController.h"
#import "BlockListUIUtils.h"
#import "ContactTableViewCell.h"
#import "Environment.h"
#import "FunctionalUtil.h"
#import "OWSContactsManager.h"
#import "SecurityUtils.h"
#import "SignalKeyingStorage.h"
#import "SignalsViewController.h"
#import "TSOutgoingMessage.h"
#import "UIImage+normalizeImage.h"
#import "UIUtil.h"
#import <MobileCoreServices/UTCoreTypes.h>
#import <SignalServiceKit/MimeTypeUtil.h>
#import <SignalServiceKit/NSDate+millisecondTimeStamp.h>
#import <SignalServiceKit/OWSBlockingManager.h>
#import <SignalServiceKit/OWSMessageSender.h>
#import <SignalServiceKit/TSAccountManager.h>

static NSString *const kUnwindToMessagesViewSegue = @"UnwindToMessagesViewSegue";

@interface NewGroupViewController () {
    NSArray *contacts;
}

@property TSGroupThread *thread;
@property (nonatomic, readonly, strong) OWSMessageSender *messageSender;
@property (nonatomic, readonly, strong) OWSContactsManager *contactsManager;

@property (nonatomic, readonly) OWSBlockingManager *blockingManager;
@property (nonatomic, readonly) NSArray<NSString *> *blockedPhoneNumbers;


@end

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

- (instancetype)initWithCoder:(NSCoder *)aDecoder
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
    _contactsManager = [Environment getCurrent].contactsManager;

    _blockingManager = [OWSBlockingManager sharedManager];
    _blockedPhoneNumbers = [_blockingManager blockedPhoneNumbers];

    [self observeNotifications];
}

- (void)observeNotifications
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(signalRecipientsDidChange:)
                                                 name:OWSContactsManagerSignalRecipientsDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(blockedPhoneNumbersDidChange:)
                                                 name:kNSNotificationName_BlockedPhoneNumbersDidChange
                                               object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)signalRecipientsDidChange:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateContacts];
    });
}

- (void)blockedPhoneNumbersDidChange:(id)notification
{
    dispatch_async(dispatch_get_main_queue(), ^{
        _blockedPhoneNumbers = [_blockingManager blockedPhoneNumbers];

        [self updateContacts];
    });
}

- (void)updateContacts {
    AssertIsOnMainThread();

    // Snapshot selection state.
    NSMutableSet *selectedContacts = [NSMutableSet set];
    for (NSIndexPath *indexPath in [self.tableView indexPathsForSelectedRows]) {
        Contact *contact = contacts[(NSUInteger)indexPath.row];
        [selectedContacts addObject:contact];
    }

    contacts = [self filteredContacts];

    [self.tableView reloadData];

    // Restore selection state.
    for (Contact *contact in selectedContacts) {
        if ([contacts containsObject:contact]) {
            NSInteger row = (NSInteger)[contacts indexOfObject:contact];
            [self.tableView selectRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:0]
                                        animated:NO
                                  scrollPosition:UITableViewScrollPositionNone];
        }
    }
}

- (BOOL)isContactHidden:(Contact *)contact
{
    if (contact.parsedPhoneNumbers.count < 1) {
        // Hide contacts without any valid phone numbers.
        return YES;
    }

    if ([self isCurrentUserContact:contact]) {
        // We never want to add ourselves to a group.
        return YES;
    }

    return NO;
}

- (BOOL)isContactBlocked:(Contact *)contact
{
    if (contact.parsedPhoneNumbers.count < 1) {
        // Hide contacts without any valid phone numbers.
        return NO;
    }

    for (PhoneNumber *phoneNumber in contact.parsedPhoneNumbers) {
        if ([_blockedPhoneNumbers containsObject:phoneNumber.toE164]) {
            return YES;
        }
    }

    return NO;
}

- (BOOL)isCurrentUserContact:(Contact *)contact
{
    for (PhoneNumber *phoneNumber in contact.parsedPhoneNumbers) {
        if ([[phoneNumber toE164] isEqualToString:[TSAccountManager localNumber]]) {
            return YES;
        }
    }

    return NO;
}

- (NSArray<Contact *> *_Nonnull)filteredContacts
{
    NSMutableArray<Contact *> *result = [NSMutableArray new];
    for (Contact *contact in self.contactsManager.signalContacts) {
        if (![self isContactHidden:contact]) {
            [result addObject:contact];
        }
    }
    return [result copy];
}

- (BOOL)isContactInGroup:(Contact *)contact
{
    for (PhoneNumber *phoneNumber in contact.parsedPhoneNumbers) {
        if (_thread != nil && _thread.groupModel.groupMemberIds) {
            // TODO: What if a contact has two phone numbers that
            // correspond to signal account and one has been added
            // to the group but not the other?
            if ([_thread.groupModel.groupMemberIds containsObject:[phoneNumber toE164]]) {
                return YES;
            }
        }
    }

    return NO;
}

- (void)configWithThread:(TSGroupThread *)gThread {
    _thread = gThread;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.navigationController.navigationBar setTranslucent:NO];

    contacts = [self filteredContacts];

    self.tableView.tableHeaderView.frame = CGRectMake(0, 0, 400, 44);
    self.tableView.tableHeaderView       = self.tableView.tableHeaderView;

    [self initializeDelegates];
    [self initializeTableView];
    [self initializeKeyboardHandlers];

    if (_thread == nil) {
        self.navigationItem.rightBarButtonItem =
            [[UIBarButtonItem alloc] initWithImage:[[UIImage imageNamed:@"add-conversation"]
                                                       imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal]
                                             style:UIBarButtonItemStylePlain
                                            target:self
                                            action:@selector(createGroup)];
        self.navigationItem.rightBarButtonItem.imageInsets = UIEdgeInsetsMake(0, -10, 0, 10);
        self.navigationItem.title                          = NSLocalizedString(@"NEW_GROUP_DEFAULT_TITLE", @"");
        self.navigationItem.rightBarButtonItem.accessibilityLabel = NSLocalizedString(@"FINISH_GROUP_CREATION_LABEL", @"Accessibilty label for finishing new group");
    } else {
        self.navigationItem.rightBarButtonItem =
            [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"UPDATE_BUTTON_TITLE", @"")
                                             style:UIBarButtonItemStylePlain
                                            target:self
                                            action:@selector(updateGroup)];
        self.navigationItem.title    = _thread.groupModel.groupName;
        self.nameGroupTextField.text = _thread.groupModel.groupName;
        if (_thread.groupModel.groupImage != nil) {
            _groupImage = _thread.groupModel.groupImage;
            [self setupGroupImageButton:_thread.groupModel.groupImage];
        }
    }
    _nameGroupTextField.placeholder = NSLocalizedString(@"NEW_GROUP_NAMEGROUP_REQUEST_DEFAULT", @"");
    _addPeopleLabel.text            = NSLocalizedString(@"NEW_GROUP_REQUEST_ADDPEOPLE", @"");
}

#pragma mark - Initializers

- (void)initializeDelegates {
    self.nameGroupTextField.delegate = self;
}

- (void)initializeTableView {
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
}

#pragma mark - Keyboard notifications

- (void)initializeKeyboardHandlers {
    UITapGestureRecognizer *outsideTabRecognizer =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboardFromAppropriateSubView)];
    [self.tapToDismissView addGestureRecognizer:outsideTabRecognizer];
}

- (void)dismissKeyboardFromAppropriateSubView {
    [self.nameGroupTextField resignFirstResponder];
}


#pragma mark - Actions
- (void)createGroup
{
    TSGroupModel *model = [self makeGroup];

    [[TSStorageManager sharedManager]
            .dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
      self.thread = [TSGroupThread getOrCreateThreadWithGroupModel:model transaction:transaction];
    }];

    void (^popToThread)() = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [self dismissViewControllerAnimated:YES
                                     completion:^{
                                         [Environment messageGroup:self.thread];
                                     }];

        });
    };

    void (^removeThreadWithError)(NSError *error) = ^(NSError *error) {
        [self.thread remove];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self dismissViewControllerAnimated:YES
                                     completion:^{
                                         SignalAlertView(NSLocalizedString(@"GROUP_CREATING_FAILED", nil),
                                             error.localizedDescription);
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
                                                                 inThread:self.thread
                                                              messageBody:@""
                                                            attachmentIds:[NSMutableArray new]];

                         message.groupMetaMessage = TSGroupMessageNew;
                         message.customMessage = NSLocalizedString(@"GROUP_CREATED", nil);
                         if (model.groupImage) {
                             [self.messageSender sendAttachmentData:UIImagePNGRepresentation(model.groupImage)
                                                        contentType:OWSMimeTypeImagePng
                                                          inMessage:message
                                                            success:popToThread
                                                            failure:removeThreadWithError];
                         } else {
                             [self.messageSender sendMessage:message success:popToThread failure:removeThreadWithError];
                         }
                     }];
}


- (void)updateGroup
{
    NSMutableArray *mut = [[NSMutableArray alloc] init];
    for (NSIndexPath *idx in _tableView.indexPathsForSelectedRows) {
        [mut addObjectsFromArray:[[contacts objectAtIndex:(NSUInteger)idx.row] textSecureIdentifiers]];
    }
    [mut addObjectsFromArray:_thread.groupModel.groupMemberIds];

    _groupModel = [[TSGroupModel alloc] initWithTitle:_nameGroupTextField.text
                                            memberIds:[[[NSSet setWithArray:mut] allObjects] mutableCopy]
                                                image:_thread.groupModel.groupImage
                                              groupId:_thread.groupModel.groupId];

    [self.nameGroupTextField resignFirstResponder];

    [self performSegueWithIdentifier:kUnwindToMessagesViewSegue sender:self];
}


- (TSGroupModel *)makeGroup
{
    NSString *title     = _nameGroupTextField.text;
    NSMutableArray *mut = [[NSMutableArray alloc] init];

    for (NSIndexPath *idx in _tableView.indexPathsForSelectedRows) {
        [mut addObjectsFromArray:[[contacts objectAtIndex:(NSUInteger)idx.row] textSecureIdentifiers]];
    }
    [mut addObject:[TSAccountManager localNumber]];
    NSData *groupId = [SecurityUtils generateRandomBytes:16];

    return [[TSGroupModel alloc] initWithTitle:title memberIds:mut image:_groupImage groupId:groupId];
}

- (IBAction)addGroupPhoto:(id)sender {
    UIAlertController *actionSheetController = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"NEW_GROUP_ADD_PHOTO_ACTION", @"Action Sheet title prompting the user for a group avatar")
                                                                                   message:nil
                                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    UIAlertAction *dismissAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"TXT_CANCEL_TITLE", @"")
                                                            style:UIAlertActionStyleCancel
                                                          handler:nil];
    [actionSheetController addAction:dismissAction];

    UIAlertAction *takePictureAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"MEDIA_FROM_CAMERA_BUTTON", @"media picker option to take photo or video")
                                                                style:UIAlertActionStyleDefault
                                                              handler:^(UIAlertAction * _Nonnull action) {
                                                                  [self takePicture];
                                                              }];
    [actionSheetController addAction:takePictureAction];

    UIAlertAction *choosePictureAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"MEDIA_FROM_LIBRARY_BUTTON", @"media picker option to choose from library")
                                                                  style:UIAlertActionStyleDefault
                                                                handler:^(UIAlertAction * _Nonnull action) {
                                                                    [self chooseFromLibrary];
                                                                }];
    [actionSheetController addAction:choosePictureAction];

    [self presentViewController:actionSheetController animated:true completion:nil];
}

#pragma mark - Group Image

- (void)takePicture {
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.delegate                 = self;
    picker.allowsEditing            = NO;
    picker.sourceType               = UIImagePickerControllerSourceTypeCamera;

    if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
        picker.mediaTypes = [[NSArray alloc] initWithObjects:(NSString *)kUTTypeImage, nil];
        [self presentViewController:picker animated:YES completion:[UIUtil modalCompletionBlock]];
    }
}

- (void)chooseFromLibrary {
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.delegate                 = self;
    picker.sourceType               = UIImagePickerControllerSourceTypeSavedPhotosAlbum;

    if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeSavedPhotosAlbum]) {
        picker.mediaTypes = [[NSArray alloc] initWithObjects:(NSString *)kUTTypeImage, nil];
        [self presentViewController:picker animated:YES completion:[UIUtil modalCompletionBlock]];
    }
}

/*
 *  Dismissing UIImagePickerController
 */

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [self dismissViewControllerAnimated:YES completion:nil];
}

/*
 *  Fetch data from UIImagePickerController
 */
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
    UIImage *picture_camera = [info objectForKey:UIImagePickerControllerOriginalImage];

    if (picture_camera) {
        UIImage *small = [picture_camera resizedImageToFitInSize:CGSizeMake(100.00, 100.00) scaleIfSmaller:NO];
        _thread.groupModel.groupImage = small;
        _groupImage                   = small;
        [self setupGroupImageButton:small];
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)setupGroupImageButton:(UIImage *)image {
    [_groupImageButton setImage:image forState:UIControlStateNormal];
    _groupImageButton.imageView.layer.cornerRadius  = CGRectGetWidth([_groupImageButton.imageView frame]) / 2.0f;
    _groupImageButton.imageView.layer.masksToBounds = YES;
    _groupImageButton.imageView.layer.borderColor   = [[UIColor lightGrayColor] CGColor];
    _groupImageButton.imageView.layer.borderWidth   = 0.5f;
    _groupImageButton.imageView.contentMode = UIViewContentModeScaleAspectFill;
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)[contacts count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    ContactTableViewCell *cell
        = (ContactTableViewCell *)[tableView dequeueReusableCellWithIdentifier:[ContactTableViewCell reuseIdentifier]];
    if (!cell) {
        cell = [ContactTableViewCell new];
    }

    [self updateContentsOfCell:cell indexPath:indexPath];

    return cell;
}

- (void)updateContentsOfCell:(ContactTableViewCell *)cell indexPath:(NSIndexPath *)indexPath
{
    OWSAssert(cell);
    OWSAssert(indexPath);

    Contact *contact = contacts[(NSUInteger)indexPath.row];
    BOOL isBlocked = [self isContactBlocked:contact];
    BOOL isInGroup = [self isContactInGroup:contact];
    BOOL isSelected = [[self.tableView indexPathsForSelectedRows] containsObject:indexPath];
    // More than one of these conditions might be true.
    // In order of priority...
    cell.accessoryMessage = nil;
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    if (isInGroup) {
        OWSAssert(!isSelected);
        // ...if the user is already in the group, indicate that.
        cell.accessoryMessage = NSLocalizedString(
            @"CONTACT_CELL_IS_IN_GROUP", @"An indicator that a contact is a member of the current group.");
    } else if (isSelected) {
        // ...if the user is being added to the group, indicate that.
        cell.accessoryType = UITableViewCellAccessoryCheckmark;
    } else if (isBlocked) {
        // ...if the user is blocked, indicate that.
        cell.accessoryMessage
            = NSLocalizedString(@"CONTACT_CELL_IS_BLOCKED", @"An indicator that a contact has been blocked.");
    }
    [cell configureWithContact:contact contactsManager:self.contactsManager];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return [ContactTableViewCell rowHeight];
}

#pragma mark - Table View delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    Contact *contact = contacts[(NSUInteger)indexPath.row];
    BOOL isBlocked = [self isContactBlocked:contact];
    BOOL isInGroup = [self isContactInGroup:contact];
    if (isInGroup) {
        // Deselect.
        [tableView deselectRowAtIndexPath:indexPath animated:YES];

        NSString *displayName = [_contactsManager displayNameForContact:contact];
        UIAlertController *controller = [UIAlertController
            alertControllerWithTitle:
                NSLocalizedString(@"EDIT_GROUP_VIEW_ALREADY_IN_GROUP_ALERT_TITLE",
                    @"A title of the alert if user tries to add a user to a group who is already in the group.")
                             message:[NSString
                                         stringWithFormat:
                                             NSLocalizedString(@"EDIT_GROUP_VIEW_ALREADY_IN_GROUP_ALERT_MESSAGE_FORMAT",
                                                 @"A format for the message of the alert if user tries to "
                                                 @"add a user to a group who is already in the group.  Embeds {{the "
                                                 @"blocked user's name or phone number}}."),
                                         displayName]
                      preferredStyle:UIAlertControllerStyleAlert];
        [controller addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil)
                                                       style:UIAlertActionStyleDefault
                                                     handler:nil]];
        [self presentViewController:controller animated:YES completion:nil];
        return;
    } else if (isBlocked) {
        // Deselect.
        [self.tableView deselectRowAtIndexPath:indexPath animated:YES];

        __weak NewGroupViewController *weakSelf = self;
        [BlockListUIUtils showUnblockContactActionSheet:contact
                                     fromViewController:self
                                        blockingManager:_blockingManager
                                        contactsManager:_contactsManager
                                        completionBlock:^(BOOL isStillBlocked) {
                                            if (!isStillBlocked) {
                                                // Re-select.
                                                [weakSelf.tableView selectRowAtIndexPath:indexPath
                                                                                animated:YES
                                                                          scrollPosition:UITableViewScrollPositionNone];

                                                ContactTableViewCell *cell = (ContactTableViewCell *)[weakSelf.tableView
                                                    cellForRowAtIndexPath:indexPath];
                                                [weakSelf updateContentsOfCell:cell indexPath:indexPath];
                                            }
                                        }];
        return;
    }

    ContactTableViewCell *cell = (ContactTableViewCell *)[self.tableView cellForRowAtIndexPath:indexPath];
    [self updateContentsOfCell:cell indexPath:indexPath];
}

- (void)tableView:(UITableView *)tableView didDeselectRowAtIndexPath:(NSIndexPath *)indexPath {
    ContactTableViewCell *cell = (ContactTableViewCell *)[self.tableView cellForRowAtIndexPath:indexPath];
    [self updateContentsOfCell:cell indexPath:indexPath];
}

#pragma mark - Text Field Delegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self.nameGroupTextField resignFirstResponder];
    return NO;
}

#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    [self.nameGroupTextField resignFirstResponder];
}

@end
