//
//  NewGroupViewController.m
//  Signal
//
//  Created by Dylan Bourgeois on 13/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "NewGroupViewController.h"
#import "SignalsViewController.h"
#import "Contact.h"
#import "ContactsManager.h"
#import "Environment.h"
#import "FunctionalUtil.h"


#import "Contact.h"
#import "TSGroupModel.h"
#import "SecurityUtils.h"
#import "SignalKeyingStorage.h"

#import "UIImage+normalizeImage.h"

#import "UIUtil.h"
#import "DJWActionSheet+OWS.h"
#import <MobileCoreServices/UTCoreTypes.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>

static NSString* const kUnwindToMessagesViewSegue = @"UnwindToMessagesViewSegue";

@interface NewGroupViewController () {
    NSArray* contacts;
}
@property TSGroupThread* thread;

@end
@implementation NewGroupViewController

- (void)configWithThread:(TSGroupThread *)gThread{
    _thread = gThread;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.navigationController.navigationBar setTranslucent:NO];

    contacts = [Environment getCurrent].contactsManager.textSecureContacts;

    contacts = [contacts filter:^int(Contact* contact) {
        for(PhoneNumber* number in [contact parsedPhoneNumbers]) {
            if([[number toE164] isEqualToString:[SignalKeyingStorage.localNumber toE164]]) {
                return NO;
            }
        }
        return YES;
    }];
    
    [self initializeDelegates];
    [self initializeTableView];
    [self initializeKeyboardHandlers];

    if(_thread==nil) {
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]initWithTitle:@"Create" style:UIBarButtonItemStylePlain target:self action:@selector(createGroup)];
        self.navigationItem.title = @"New Group";
        
    }
    else {
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]initWithTitle:@"Update" style:UIBarButtonItemStylePlain target:self action:@selector(updateGroup)];
        self.navigationItem.title = _thread.groupModel.groupName;
        self.nameGroupTextField.text = _thread.groupModel.groupName;
        if(_thread.groupModel.groupImage!=nil) {
            [self setupGroupImageButton:_thread.groupModel.groupImage];
        }
        // Select the contacts already selected:
        for (NSInteger r = 0; r < [_tableView numberOfRowsInSection:0]-1; r++) {
            // TODOGROUP this will not scale well
            NSMutableSet *usersInGroup = [NSMutableSet setWithArray:_thread.groupModel.groupMemberIds];
            NSMutableArray *contactPhoneNumbers = [[NSMutableArray alloc] init];
            for(PhoneNumber* number in [[contacts objectAtIndex:(NSUInteger)r] parsedPhoneNumbers]) {
                [contactPhoneNumbers addObject:[number toE164]];
            }
            [usersInGroup intersectSet:[NSSet setWithArray:contactPhoneNumbers]];
            if([usersInGroup count]>0) {
                [_tableView selectRowAtIndexPath:[NSIndexPath indexPathForRow:(r+1) inSection:0]
                                        animated:NO
                                  scrollPosition:UITableViewScrollPositionNone];
            }
        }
        
    }

}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

#pragma mark - Initializers

-(void)initializeDelegates
{
    self.nameGroupTextField.delegate = self;
}

-(void)initializeTableView
{
    self.tableView.tableFooterView = [[UIView alloc]initWithFrame:CGRectZero];
}

#pragma mark - Keyboard notifications

- (void)initializeKeyboardHandlers{
    UITapGestureRecognizer *outsideTabRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboardFromAppropriateSubView)];
    [self.tapToDismissView addGestureRecognizer:outsideTabRecognizer];
}

-(void) dismissKeyboardFromAppropriateSubView {
    [self.nameGroupTextField resignFirstResponder];
}



#pragma mark - Actions
-(void)createGroup {
    TSGroupModel* model = [self makeGroup];
    [Environment groupModel:model];
}


-(void)updateGroup {
    NSMutableArray* mut = [[NSMutableArray alloc]init];
    for (NSIndexPath* idx in _tableView.indexPathsForSelectedRows) {
        [mut addObjectsFromArray:[[contacts objectAtIndex:(NSUInteger)idx.row-1] textSecureIdentifiers]];
    }
    [mut addObject:[SignalKeyingStorage.localNumber toE164]];   // Also add the originator
    _groupModel = [[TSGroupModel alloc] initWithTitle:_nameGroupTextField.text memberIds:[NSMutableArray arrayWithArray:[[NSSet setWithArray:mut] allObjects]] image:_thread.groupModel.groupImage groupId:_thread.groupModel.groupId];

    [self performSegueWithIdentifier:kUnwindToMessagesViewSegue sender:self];
}


-(TSGroupModel*)makeGroup {
    NSString* title = _nameGroupTextField.text;
    UIImage* img = _thread.groupModel.groupImage;
    NSMutableArray* mut = [[NSMutableArray alloc]init];
    
    for (NSIndexPath* idx in _tableView.indexPathsForSelectedRows) {
        [mut addObjectsFromArray:[[contacts objectAtIndex:(NSUInteger)idx.row-1] textSecureIdentifiers]];
    }
    // Also add the originator
    [mut addObject:[SignalKeyingStorage.localNumber toE164]];
    NSData* groupId =  [SecurityUtils generateRandomBytes:16];
    
    return [[TSGroupModel alloc] initWithTitle:title memberIds:mut image:img groupId:groupId];
}

-(IBAction)addGroupPhoto:(id)sender
{
    [self.nameGroupTextField resignFirstResponder];
    [DJWActionSheet showInView:self.parentViewController.view withTitle:nil cancelButtonTitle:@"Cancel"
        destructiveButtonTitle:nil otherButtonTitles:@[@"Take a Picture",@"Choose from Library"]
                      tapBlock:^(DJWActionSheet *actionSheet, NSInteger tappedButtonIndex) {
                          
        if (tappedButtonIndex == actionSheet.cancelButtonIndex) {
            NSLog(@"User Cancelled");
        } else if (tappedButtonIndex == actionSheet.destructiveButtonIndex) {
            NSLog(@"Destructive button tapped");
        }else {
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

-(void)takePicture
{
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.delegate = self;
    picker.allowsEditing = NO;
    picker.sourceType = UIImagePickerControllerSourceTypeCamera;
    
    if ([UIImagePickerController isSourceTypeAvailable:
         UIImagePickerControllerSourceTypeCamera])
    {
        picker.mediaTypes = [[NSArray alloc] initWithObjects: (NSString *)kUTTypeImage,  nil];
        [self presentViewController:picker animated:YES completion:NULL];
    }
}

-(void)chooseFromLibrary
{
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.delegate = self;
    picker.sourceType = UIImagePickerControllerSourceTypeSavedPhotosAlbum;
    
    if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeSavedPhotosAlbum])
    {
        picker.mediaTypes = [[NSArray alloc] initWithObjects:(NSString *)kUTTypeImage, nil];
        [self presentViewController:picker animated:YES completion:nil];
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
-(void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info
{
    UIImage *picture_camera = [info objectForKey:UIImagePickerControllerOriginalImage];
    
    if (picture_camera) {
        UIImage *small = [picture_camera resizedImageToFitInSize:CGSizeMake(100.00,100.00) scaleIfSmaller:NO];
        _thread.groupModel.groupImage = small;
        [self setupGroupImageButton:small];

    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

-(void)setupGroupImageButton:(UIImage*)image {
    [self.groupImageButton setImage:image forState:UIControlStateNormal];
    _groupImageButton.imageView.layer.cornerRadius = 4.0f;
    _groupImageButton.imageView.clipsToBounds = YES;
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)[contacts count]+1;
    
}


- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"SearchCell"];
    
    if (cell == nil) {
        
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier: indexPath.row == 0 ? @"HeaderCell" : @"GroupSearchCell"];
    }
    if (indexPath.row > 0) {
        NSUInteger row = (NSUInteger)indexPath.row;
        Contact* contact = contacts[row-1];
        
        cell.textLabel.attributedText = [self attributedStringForContact:contact inCell:cell];
    
    } else {
        cell.textLabel.text = @"Add People:";
        cell.textLabel.textColor = [UIColor lightGrayColor];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    
    tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
    
    return cell;
}

#pragma mark - Table View delegate
-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell * cell = [tableView cellForRowAtIndexPath:indexPath];
    if(indexPath.row>0) {
        cell.accessoryType = UITableViewCellAccessoryCheckmark;
    }
}


-(void)tableView:(UITableView *)tableView didDeselectRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell * cell = [tableView cellForRowAtIndexPath:indexPath];
    if(indexPath.row>0) {
        cell.accessoryType = UITableViewCellAccessoryNone;
    }
}

#pragma mark - Text Field Delegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField{
    [self.nameGroupTextField resignFirstResponder];
    return NO;
}

#pragma mark - Cell Utility

- (NSAttributedString *)attributedStringForContact:(Contact *)contact inCell:(UITableViewCell*)cell {
    NSMutableAttributedString *fullNameAttributedString = [[NSMutableAttributedString alloc] initWithString:contact.fullName];
    
    UIFont *firstNameFont;
    UIFont *lastNameFont;
    
    if (ABPersonGetSortOrdering() == kABPersonCompositeNameFormatFirstNameFirst) {
        firstNameFont = [UIFont ows_mediumFontWithSize:cell.textLabel.font.pointSize]; 
        lastNameFont  = [UIFont ows_regularFontWithSize:cell.textLabel.font.pointSize];
    } else{
        firstNameFont = [UIFont ows_regularFontWithSize:cell.textLabel.font.pointSize];
        lastNameFont  = [UIFont ows_mediumFontWithSize:cell.textLabel.font.pointSize];
    }
    [fullNameAttributedString addAttribute:NSFontAttributeName value:firstNameFont range:NSMakeRange(0, contact.firstName.length)];
    [fullNameAttributedString addAttribute:NSFontAttributeName value:lastNameFont range:NSMakeRange(contact.firstName.length + 1, contact.lastName.length)];
    
    [fullNameAttributedString addAttribute:NSForegroundColorAttributeName value:[UIColor blackColor] range:NSMakeRange(0, contact.fullName.length)];
    
    if (ABPersonGetSortOrdering() == kABPersonCompositeNameFormatFirstNameFirst) {
        [fullNameAttributedString addAttribute:NSForegroundColorAttributeName value:[UIColor ows_darkGrayColor] range:NSMakeRange(contact.firstName.length + 1, contact.lastName.length)];
    }
    else {
        [fullNameAttributedString addAttribute:NSForegroundColorAttributeName value:[UIColor ows_darkGrayColor] range:NSMakeRange(0, contact.firstName.length)];
    }
    
    return fullNameAttributedString;
}

@end
