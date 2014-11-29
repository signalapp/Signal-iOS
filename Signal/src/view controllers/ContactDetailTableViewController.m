//
//  ContactDetailTableViewController.m
//  Signal
//
//  Created by Dylan Bourgeois on 30/10/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "ContactDetailTableViewController.h"
#import "ContactDetailCell.h"
#import "ActionContactDetailCell.h"
#import "UIUtil.h"
#import "DJWActionSheet.h"
#import "Environment.h"
#import "PhoneManager.h"

#define kImageRadius           50.0f
#define kMinRows               3
#define kFirstAdaptableCellRow 2


typedef NS_ENUM(NSInteger, CellRow) {
    kNameMainNumberCellIndexPath,
    kActionCellIndexPath,
    kShareCellIndexPath,
    kEmailCellIndexPath,
    kAnnexPhoneNumberCellIndexPath,
    kNotesCellIndexPath,
};

typedef enum {
    kNameMainNumberCellHeight      = 180,
    kNoImageCellHeight             = 87,
    kActionCellHeight              = 60,
    kShareCellHeight               = 60,
    kEmailCellHeight               = 60,
    kAnnexPhoneNumberCellHeight    = 60,
    kNotesCellHeight               = 165,
} kCellHeight;

static NSString* const kNameMainNumberCell   = @"NameMainNumberCell";
static NSString* const kActionCell           = @"ActionCell";
static NSString* const kShareCell            = @"ShareCell";
static NSString* const kEmailCell            = @"EmailCell";
static NSString* const kAnnexPhoneNumberCell = @"AnnexPhoneNumberCell";
static NSString *const kNotesCell            = @"NotesCell";
static NSString *const kContactDetailSegue   = @"DetailSegue";


@interface ContactDetailTableViewController () {
    BOOL doesImageExist;
    NSInteger numberOfRows;
}
@end

@implementation ContactDetailTableViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    doesImageExist = YES;
    self.tableView.tableFooterView = [[UIView alloc]initWithFrame:CGRectZero];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}


#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)[self numberOfRowsForContact:_contact];
}


- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell;

    switch (indexPath.row) {
        case kNameMainNumberCellIndexPath:
            cell = (ContactDetailCell*)[tableView dequeueReusableCellWithIdentifier:kNameMainNumberCell forIndexPath:indexPath];
            [self setUpNameMainUserCell:(ContactDetailCell*)cell];
            break;
        case kActionCellIndexPath:
            cell = (ActionContactDetailCell*)[tableView dequeueReusableCellWithIdentifier:kActionCell forIndexPath:indexPath];
            [self setUpActionCell:(ActionContactDetailCell*)cell];
            break;
        case kShareCellIndexPath:
            cell = [tableView dequeueReusableCellWithIdentifier:kShareCell forIndexPath:indexPath];
            break;
        default:
            cell = [self adaptableCellAtIndexPath:indexPath];
            break;
    }
    
    
    return cell;
}


-(CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    CGFloat cellHeight = 44.0f;
    
    switch (indexPath.row) {
        case kNameMainNumberCellIndexPath:
            cellHeight = doesImageExist ? kNameMainNumberCellHeight : kNoImageCellHeight;
            break;
        case kActionCellIndexPath:
            cellHeight = kActionCellHeight;
            break;
        case kShareCellIndexPath:
            cellHeight = kShareCellHeight;
            break;
        default:
            cellHeight = [self heightForAdaptableCellAtIndexPath:indexPath];
            break;
    }
    return cellHeight;
}

-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    switch (indexPath.row) {
        case kShareCellIndexPath:
            [DJWActionSheet showInView:self.tabBarController.view
                             withTitle:nil
                     cancelButtonTitle:@"Cancel"
                destructiveButtonTitle:nil
                     otherButtonTitles:@[@"Mail", @"Message", @"Airdrop", @"Other"]
                              tapBlock:^(DJWActionSheet *actionSheet, NSInteger tappedButtonIndex) {
                                  [tableView deselectRowAtIndexPath:indexPath animated:YES];
                                  if (tappedButtonIndex == actionSheet.cancelButtonIndex) {
                                      NSLog(@"User Cancelled");
                                      
                                  } else if (tappedButtonIndex == actionSheet.destructiveButtonIndex) {
                                      NSLog(@"Destructive button tapped");
                                  }else {
                                      NSLog(@"The user tapped button at index: %li", (long)tappedButtonIndex);
                                  }
                              }];
            
            break;
            
    }
}


#pragma mark - Set Up Cells

-(void)setUpActionCell:(ActionContactDetailCell*)cell
{
    Contact * c = self.contact;
    
    UIImage *callImage = [[UIImage imageNamed:@"call_dark"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    [cell.contactCallButton setImage:callImage forState:UIControlStateNormal];
    
    UIImage *messageImage = [[UIImage imageNamed:@"signals_tab"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    [cell.contactTextButton setImage:messageImage forState:UIControlStateNormal];
    
    UIImage *clearImage = [[UIImage imageNamed:@"delete_history"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    [cell.contactShredButton setImage:clearImage forState:UIControlStateNormal];
    cell.contactShredButton.tintColor = [UIColor ows_redColor];
    
    
    if (c.isRedPhoneContact)
    {
        cell.contactCallButton.tintColor = [UIColor ows_blueColor];
        [cell.contactCallButton addTarget:self action:@selector(initiateRedPhoneCall) forControlEvents:UIControlEventTouchUpInside];
    } else {
        cell.contactCallButton.tintColor = [UIColor ows_darkGrayColor];
        cell.contactCallButton.enabled = NO;
    }
    
    if (c.isTextSecureContact)
    {
        cell.contactTextButton.tintColor = [UIColor ows_blueColor];
        [cell.contactTextButton addTarget:self action:@selector(openTextSecureConversation) forControlEvents:UIControlEventTouchUpInside];
    } else {
        cell.contactTextButton.tintColor = [UIColor ows_darkGrayColor];
        cell.contactTextButton.enabled = NO;
    }
}

- (void)openTextSecureConversation{
    NSArray *textSecureIdentifiers = [self.contact textSecureIdentifiers];
    
    if (textSecureIdentifiers.count > 1) {
        [DJWActionSheet showInView:self.tabBarController.view
                         withTitle:@"What number would you like to message?"
                 cancelButtonTitle:@"Cancel"
            destructiveButtonTitle:nil
                 otherButtonTitles:textSecureIdentifiers
                          tapBlock:^(DJWActionSheet *actionSheet, NSInteger tappedButtonIndex) {
                              if (tappedButtonIndex == actionSheet.cancelButtonIndex) {
                                  DDLogVerbose(@"User Cancelled Call");
                              } else {
                                  [Environment messageIdentifier:[textSecureIdentifiers objectAtIndex:(NSUInteger)tappedButtonIndex]];
                              }
                          }];
        
    } else if (textSecureIdentifiers.count == 1){
        [Environment messageIdentifier:[textSecureIdentifiers firstObject]];
    } else{
        DDLogWarn(@"Tried to intiate a call but contact has no RedPhone identifier");
    }
}

- (void)initiateRedPhoneCall{
    NSArray *redPhoneIdentifiers = [self.contact redPhoneIdentifiers];
    
    if (redPhoneIdentifiers.count > 1) {
        
        NSMutableArray *e164 = [NSMutableArray array];
        
        for (PhoneNumber *phoneNumber in redPhoneIdentifiers) {
            [e164 addObject:phoneNumber.toE164];
        }
        
        [DJWActionSheet showInView:self.tabBarController.view
                         withTitle:@"What number would you like to dial?"
                 cancelButtonTitle:@"Cancel"
            destructiveButtonTitle:nil
                 otherButtonTitles:e164
                          tapBlock:^(DJWActionSheet *actionSheet, NSInteger tappedButtonIndex) {
                              if (tappedButtonIndex == actionSheet.cancelButtonIndex) {
                                  DDLogVerbose(@"User Cancelled Call");
                              } else {
                                  [Environment.phoneManager initiateOutgoingCallToContact:self.contact atRemoteNumber:[redPhoneIdentifiers objectAtIndex:(NSUInteger)tappedButtonIndex]];
                              }
                          }];
        
    } else if (redPhoneIdentifiers.count == 1){
        [Environment.phoneManager initiateOutgoingCallToContact:self.contact atRemoteNumber:[redPhoneIdentifiers firstObject]];
    } else{
        DDLogWarn(@"Tried to intiate a call but contact has no RedPhone identifier");
    }
}

-(void)setUpNameMainUserCell:(ContactDetailCell*)cell
{
    Contact* c = self.contact;
    
    cell.contactName.text = [c fullName];
    
    cell.contactPhoneNumber.text = [[c userTextPhoneNumbers] firstObject];
    
    if (c.image) {
        cell.contactImageView.image = c.image;
    } else {
        [cell.contactImageView addConstraint:[NSLayoutConstraint constraintWithItem:cell.contactImageView attribute:NSLayoutAttributeHeight relatedBy:0 toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1.0f constant:0]];
        doesImageExist = NO;
        
    }
    [cell.contactImageView.layer setCornerRadius:kImageRadius];
    [cell.contactImageView.layer setMasksToBounds:YES];
}

-(void)setUpEmailCell:(ContactDetailCell*)cell forIndexPath:(NSIndexPath*)indexPath
{
    cell.contactEmailLabel.text = [_contact.emails objectAtIndex:(NSUInteger)indexPath.row-kMinRows];
}

-(void)setUpAnnexNumberCell:(ContactDetailCell*)cell forIndexPath:(NSIndexPath*)indexPath
{
    NSInteger i = indexPath.row - [self emailUpperBound] ;
    
    cell.contactAnnexNumberLabel.text = [_contact.userTextPhoneNumbers objectAtIndex:(NSUInteger)i];
}

-(void)setUpNotesCell:(ContactDetailCell*)cell
{
    cell.contactNotesTextView.text = _contact.notes;
}

#pragma mark - Utilities (Adaptable Cells)

-(UITableViewCell*)adaptableCellAtIndexPath:(NSIndexPath*)indexPath
{
    ContactDetailCell * cell;
    
    if ([self isEmailIndexPath:indexPath])
    {
        cell = [self.tableView dequeueReusableCellWithIdentifier:kEmailCell forIndexPath:indexPath];
        [self setUpEmailCell:cell forIndexPath:indexPath];
        
        return cell;
    }
    
    else if ([self isAnnexNumberIndexPath:indexPath])
    {
        cell = [self.tableView dequeueReusableCellWithIdentifier:kAnnexPhoneNumberCell forIndexPath:indexPath];
        [self setUpAnnexNumberCell:cell forIndexPath:indexPath];
        
        return cell;
    }
    
    else if ([self isNotesIndexPath:indexPath])
    {
        cell = [self.tableView dequeueReusableCellWithIdentifier:kNotesCell forIndexPath:indexPath];
        [self setUpNotesCell:cell];
        
        return cell;
        
    }
    
    else
    {
        return nil;
    }
}

-(CGFloat)heightForAdaptableCellAtIndexPath:(NSIndexPath*)indexPath
{
    if ([self isEmailIndexPath:indexPath])
    {
        return kEmailCellHeight;
    }
    
    else if ([self isAnnexNumberIndexPath:indexPath])
    {
        return kAnnexPhoneNumberCellHeight;
    }
    
    else if ([self isNotesIndexPath:indexPath])
    {
        return kNotesCellHeight;
    }
    
    else
    {
        return 44.0f;
    }
    
}

#pragma mark - IndexPaths

-(BOOL)isEmailIndexPath:(NSIndexPath*)indexPath
{
    return indexPath.row > kFirstAdaptableCellRow && indexPath.row <= [self emailUpperBound];
}

-(BOOL)isAnnexNumberIndexPath:(NSIndexPath*)indexPath
{
    return indexPath.row > [self emailUpperBound]  && indexPath.row <  [self phoneNumberUpperBound];
}

-(BOOL)isNotesIndexPath:(NSIndexPath*)indexPath
{
    return indexPath.row == (NSInteger)[self numberOfRowsForContact:_contact]-1;
}

#pragma mark - Utilities (Bounds)

-(NSInteger)emailUpperBound
{
    return (NSInteger)(kFirstAdaptableCellRow+_contact.emails.count);
}

-(NSInteger)phoneNumberUpperBound
{
    return [self emailUpperBound] + (NSInteger)_contact.userTextPhoneNumbers.count;
}

-(NSUInteger)numberOfRowsForContact:(Contact*)contact
{
    NSUInteger numNotes = contact.notes.length == 0 ? 0 : 1;
    NSUInteger numEmails = contact.emails.count;
    NSUInteger numPhoneNumbers = contact.userTextPhoneNumbers.count-1;
    
    return kMinRows + numEmails + numPhoneNumbers + numNotes;
}

@end
