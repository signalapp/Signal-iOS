//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "NewGroupViewController.h"
#import "Environment.h"
#import "FunctionalUtil.h"
#import "OWSContactsManager.h"
#import "SecurityUtils.h"
#import "SignalKeyingStorage.h"
#import "SignalsViewController.h"
#import "TSOutgoingMessage.h"
#import "UIImage+normalizeImage.h"
#import "UIUtil.h"
#import "UIViewController+OWS.h"
#import <MobileCoreServices/UTCoreTypes.h>
#import <SignalServiceKit/MimeTypeUtil.h>
#import <SignalServiceKit/NSDate+millisecondTimeStamp.h>
#import <SignalServiceKit/OWSMessageSender.h>
#import <SignalServiceKit/TSAccountManager.h>

static NSString *const kUnwindToMessagesViewSegue = @"UnwindToMessagesViewSegue";

@interface NewGroupViewController () {
    NSArray *contacts;
}

@property TSGroupThread *thread;
@property (nonatomic, readonly, strong) OWSMessageSender *messageSender;
@property (nonatomic, readonly, strong) OWSContactsManager *contactsManager;

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
    _messageSender = [[OWSMessageSender alloc] initWithNetworkManager:[Environment getCurrent].networkManager
                                                       storageManager:[TSStorageManager sharedManager]
                                                      contactsManager:[Environment getCurrent].contactsManager
                                                      contactsUpdater:[Environment getCurrent].contactsUpdater];

    _contactsManager = [Environment getCurrent].contactsManager;

    [self observeNotifications];
}

- (void)observeNotifications
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(signalRecipientsDidChange:)
                                                 name:OWSContactsManagerSignalRecipientsDidChangeNotification
                                               object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)signalRecipientsDidChange:(NSNotification *)notification {
    [self updateContacts];
}

- (void)updateContacts {
    AssertIsOnMainThread();

    contacts = self.contactsManager.signalContacts;

    [self.tableView reloadData];
}

- (void)configWithThread:(TSGroupThread *)gThread {
    _thread = gThread;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.navigationController.navigationBar setTranslucent:NO];
    [self useOWSBackButton];
    
    contacts = self.contactsManager.signalContacts;


    self.tableView.tableHeaderView.frame = CGRectMake(0, 0, 400, 44);
    self.tableView.tableHeaderView       = self.tableView.tableHeaderView;


    contacts = [contacts filter:^int(Contact *contact) {
      for (PhoneNumber *number in [contact parsedPhoneNumbers]) {
          if ([[number toE164] isEqualToString:[TSAccountManager localNumber]]) {
              // remove local number
              return NO;
          } else if (_thread != nil && _thread.groupModel.groupMemberIds) {
              return ![_thread.groupModel.groupMemberIds containsObject:[number toE164]];
          }
      }
      return YES;
    }];

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
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"SearchCell"];

    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"GroupSearchCell"];
    }

    NSUInteger row   = (NSUInteger)indexPath.row;
    Contact *contact = contacts[row];

    cell.textLabel.attributedText = [self.contactsManager formattedFullNameForContact:contact font:cell.textLabel.font];

    tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];

    if ([[tableView indexPathsForSelectedRows] containsObject:indexPath]) {
        [self adjustSelected:cell];
    }

    return cell;
}

#pragma mark - Table View delegate
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    [self adjustSelected:cell];
}

- (void)adjustSelected:(UITableViewCell *)cell {
    cell.accessoryType = UITableViewCellAccessoryCheckmark;
}

- (void)tableView:(UITableView *)tableView didDeselectRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    cell.accessoryType    = UITableViewCellAccessoryNone;
}

#pragma mark - Text Field Delegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self.nameGroupTextField resignFirstResponder];
    return NO;
}

@end
