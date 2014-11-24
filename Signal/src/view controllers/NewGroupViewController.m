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

#import "Contact.h"
#import "DemoDataFactory.h"
#import "GroupModel.h"

#import "UIUtil.h"
#import "DJWActionSheet.h"
#import <MobileCoreServices/UTCoreTypes.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>

@interface NewGroupViewController () {
    NSArray* contacts;
}

@end

@implementation NewGroupViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]initWithTitle:@"Create" style:UIBarButtonItemStylePlain target:self action:@selector(createGroup)];
    self.navigationItem.title = @"New Group";
    
    contacts = [Environment getCurrent].contactsManager.textSecureContacts;
    
    [self initializeDelegates];
    [self initializeTableView];
    [self initializeKeyboardHandlers];
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
    SignalsViewController* s = (SignalsViewController*)((UINavigationController*)[((UITabBarController*)self.parentViewController.presentingViewController).childViewControllers objectAtIndex:1]).topViewController;
    
    s.groupFromCompose = [self makeGroup];
    
    [self dismissViewControllerAnimated:YES completion:^(){
        [s performSegueWithIdentifier:@"showSegue" sender:nil];
    }];
}

-(GroupModel*)makeGroup {
    
    //TODO: Add it to Envirronment
    
    NSString* title = _nameGroupTextField.text;
    UIImage* img = _groupImageButton.imageView.image;
    NSMutableArray* mut = [[NSMutableArray alloc]init];
    
    for (NSIndexPath* idx in _tableView.indexPathsForSelectedRows) {
        [mut addObject:[contacts objectAtIndex:(NSUInteger)idx.row-1]];
    }
    
    return [[GroupModel alloc] initWithTitle:title members:mut image:img];
}

-(IBAction)addGroupPhoto:(id)sender
{
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
        //There is a photo
        _groupImageButton.imageView.image = picture_camera;
        _groupImageButton.imageView.layer.cornerRadius = 40.0f;
        _groupImageButton.imageView.clipsToBounds = YES;
        
    }
    
    [self dismissViewControllerAnimated:YES completion:nil];
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
    }
    
    tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
    
    return cell;
}

#pragma mark - Table View delegate
-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell * cell = [tableView cellForRowAtIndexPath:indexPath];
    cell.accessoryType = UITableViewCellAccessoryCheckmark;
    
}


-(void)tableView:(UITableView *)tableView didDeselectRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell * cell = [tableView cellForRowAtIndexPath:indexPath];
    cell.accessoryType = UITableViewCellAccessoryNone;
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
        firstNameFont = [UIFont ows_lightFontWithSize:cell.textLabel.font.pointSize];
        lastNameFont  = [UIFont systemFontOfSize:cell.textLabel.font.pointSize];
    } else{
        firstNameFont = [UIFont ows_lightFontWithSize:cell.textLabel.font.pointSize];
        lastNameFont  = [UIFont systemFontOfSize:cell.textLabel.font.pointSize];
    }
    [fullNameAttributedString addAttribute:NSFontAttributeName value:firstNameFont range:NSMakeRange(0, contact.firstName.length)];
    [fullNameAttributedString addAttribute:NSFontAttributeName value:lastNameFont range:NSMakeRange(contact.firstName.length + 1, contact.lastName.length)];
    
    [fullNameAttributedString addAttribute:NSForegroundColorAttributeName value:[UIColor blackColor] range:NSMakeRange(0, contact.fullName.length)];
    return fullNameAttributedString;
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
