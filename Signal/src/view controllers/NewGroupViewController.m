//
//  NewGroupViewController.m
//  Signal
//
//  Created by Dylan Bourgeois on 13/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <MobileCoreServices/UTCoreTypes.h>
#import <TextSecureKit/NSDate+millisecondTimeStamp.h>
#import <TextSecureKit/TSAccountManager.h>
#import <TextSecureKit/TSMessagesManager+attachments.h>
#import <TextSecureKit/TSMessagesManager+sendMessages.h>
#import "ContactsManager.h"
#import "DJWActionSheet+OWS.h"
#import "Environment.h"
#import "FunctionalUtil.h"
#import "NewGroupViewController.h"
#import "SecurityUtils.h"
#import "SignalKeyingStorage.h"
#import "SignalsViewController.h"
#import "TSOutgoingMessage.h"
#import "UIImage+normalizeImage.h"
#import "UIUtil.h"

static NSString *const kUnwindToMessagesViewSegue = @"UnwindToMessagesViewSegue";

@interface NewGroupViewController () {
    NSArray *contacts;
}
@property TSGroupThread *thread;

@end
@implementation NewGroupViewController

- (void)configWithThread:(TSGroupThread *)gThread {
    _thread = gThread;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.navigationController.navigationBar setTranslucent:NO];

    contacts = [Environment getCurrent].contactsManager.textSecureContacts;


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

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
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
- (void)createGroup {
    TSGroupModel *model = [self makeGroup];

    [[TSStorageManager sharedManager]
            .dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
      self.thread = [TSGroupThread getOrCreateThreadWithGroupModel:model transaction:transaction];
    }];

    UIAlertController *alertController =
        [UIAlertController alertControllerWithTitle:NSLocalizedString(@"GROUP_CREATING", nil)
                                            message:nil
                                     preferredStyle:UIAlertControllerStyleAlert];
    [self
        presentViewController:alertController
                     animated:YES
                   completion:^{
                     TSOutgoingMessage *message =
                         [[TSOutgoingMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                             inThread:self.thread
                                                          messageBody:@""
                                                          attachments:[[NSMutableArray alloc] init]];
                     message.groupMetaMessage = TSGroupMessageNew;
                     if (model.groupImage != nil) {
                         [[TSMessagesManager sharedManager] sendAttachment:UIImagePNGRepresentation(model.groupImage)
                             contentType:@"image/png"
                             inMessage:message
                             thread:self.thread
                             success:^{
                               [self dismissViewControllerAnimated:YES
                                                        completion:^{
                                                          [Environment messageGroup:self.thread];
                                                        }];
                             }

                             failure:^{
                               [self
                                   dismissViewControllerAnimated:YES
                                                      completion:^{

                                                        [[TSStorageManager sharedManager]
                                                                .dbConnection
                                                            readWriteWithBlock:^(
                                                                YapDatabaseReadWriteTransaction *_Nonnull transaction) {
                                                              [self.thread removeWithTransaction:transaction];
                                                            }];

                                                        SignalAlertView(
                                                            NSLocalizedString(@"GROUP_CREATING_FAILED", nil),
                                                            NSLocalizedString(@"NETWORK_ERROR_RECOVERY", nil));
                                                      }];

                             }];
                     } else {
                         [[TSMessagesManager sharedManager] sendMessage:message
                             inThread:self.thread
                             success:^{
                               [self dismissViewControllerAnimated:YES
                                                        completion:^{
                                                          [Environment messageGroup:self.thread];
                                                        }];
                             }

                             failure:^{
                               [self
                                   dismissViewControllerAnimated:YES
                                                      completion:^{

                                                        [[TSStorageManager sharedManager]
                                                                .dbConnection
                                                            readWriteWithBlock:^(
                                                                YapDatabaseReadWriteTransaction *_Nonnull transaction) {
                                                              [self.thread removeWithTransaction:transaction];
                                                            }];

                                                        SignalAlertView(
                                                            NSLocalizedString(@"GROUP_CREATING_FAILED", nil),
                                                            NSLocalizedString(@"NETWORK_ERROR_RECOVERY", nil));
                                                      }];


                             }];
                     }
                   }];
}


- (void)updateGroup {
    NSMutableArray *mut = [[NSMutableArray alloc] init];
    for (NSIndexPath *idx in _tableView.indexPathsForSelectedRows) {
        [mut addObjectsFromArray:[[contacts objectAtIndex:(NSUInteger)idx.row] textSecureIdentifiers]];
    }
    [mut addObjectsFromArray:_thread.groupModel.groupMemberIds];

    _groupModel = [[TSGroupModel alloc] initWithTitle:_nameGroupTextField.text
                                            memberIds:[[[NSSet setWithArray:mut] allObjects] mutableCopy]
                                                image:_thread.groupModel.groupImage
                                              groupId:_thread.groupModel.groupId
                               associatedAttachmentId:nil];

    [self.nameGroupTextField resignFirstResponder];

    [self performSegueWithIdentifier:kUnwindToMessagesViewSegue sender:self];
}


- (TSGroupModel *)makeGroup {
    NSString *title     = _nameGroupTextField.text;
    NSMutableArray *mut = [[NSMutableArray alloc] init];

    for (NSIndexPath *idx in _tableView.indexPathsForSelectedRows) {
        [mut addObjectsFromArray:[[contacts objectAtIndex:(NSUInteger)idx.row] textSecureIdentifiers]];
    }
    [mut addObject:[TSAccountManager localNumber]];
    NSData *groupId = [SecurityUtils generateRandomBytes:16];

    return [[TSGroupModel alloc] initWithTitle:title
                                     memberIds:mut
                                         image:_groupImage
                                       groupId:groupId
                        associatedAttachmentId:nil];
}

- (IBAction)addGroupPhoto:(id)sender {
    [self.nameGroupTextField resignFirstResponder];
    [DJWActionSheet showInView:self.parentViewController.view
                     withTitle:nil
             cancelButtonTitle:NSLocalizedString(@"TXT_CANCEL_TITLE", @"")
        destructiveButtonTitle:nil
             otherButtonTitles:@[
                 NSLocalizedString(@"TAKE_PICTURE_BUTTON", @""),
                 NSLocalizedString(@"CHOOSE_MEDIA_BUTTON", @"")
             ]
                      tapBlock:^(DJWActionSheet *actionSheet, NSInteger tappedButtonIndex) {

                        if (tappedButtonIndex == actionSheet.cancelButtonIndex) {
                            DDLogDebug(@"User Cancelled");
                        } else if (tappedButtonIndex == actionSheet.destructiveButtonIndex) {
                            DDLogDebug(@"Destructive button tapped");
                        } else {
                            switch (tappedButtonIndex) {
                                case 0:
                                    [self takePicture];
                                    break;
                                case 1:
                                    [self chooseFromLibrary];
                                    break;
                                default:
                                    break;
                            }
                        }
                      }];
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

    cell.textLabel.attributedText = [self attributedStringForContact:contact inCell:cell];

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

#pragma mark - Cell Utility

- (NSAttributedString *)attributedStringForContact:(Contact *)contact inCell:(UITableViewCell *)cell {
    NSMutableAttributedString *fullNameAttributedString =
        [[NSMutableAttributedString alloc] initWithString:contact.fullName];

    UIFont *firstNameFont;
    UIFont *lastNameFont;

    if (ABPersonGetSortOrdering() == kABPersonCompositeNameFormatFirstNameFirst) {
        firstNameFont = [UIFont ows_mediumFontWithSize:cell.textLabel.font.pointSize];
        lastNameFont  = [UIFont ows_regularFontWithSize:cell.textLabel.font.pointSize];
    } else {
        firstNameFont = [UIFont ows_regularFontWithSize:cell.textLabel.font.pointSize];
        lastNameFont  = [UIFont ows_mediumFontWithSize:cell.textLabel.font.pointSize];
    }
    [fullNameAttributedString addAttribute:NSFontAttributeName
                                     value:firstNameFont
                                     range:NSMakeRange(0, contact.firstName.length)];
    [fullNameAttributedString addAttribute:NSFontAttributeName
                                     value:lastNameFont
                                     range:NSMakeRange(contact.firstName.length + 1, contact.lastName.length)];

    [fullNameAttributedString addAttribute:NSForegroundColorAttributeName
                                     value:[UIColor blackColor]
                                     range:NSMakeRange(0, contact.fullName.length)];

    if (ABPersonGetSortOrdering() == kABPersonCompositeNameFormatFirstNameFirst) {
        [fullNameAttributedString addAttribute:NSForegroundColorAttributeName
                                         value:[UIColor ows_darkGrayColor]
                                         range:NSMakeRange(contact.firstName.length + 1, contact.lastName.length)];
    } else {
        [fullNameAttributedString addAttribute:NSForegroundColorAttributeName
                                         value:[UIColor ows_darkGrayColor]
                                         range:NSMakeRange(0, contact.firstName.length)];
    }

    return fullNameAttributedString;
}

@end
