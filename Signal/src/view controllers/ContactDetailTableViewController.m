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

#define kImageRadius 50.0f
#define kMinRows 4
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
    UITableViewCell * cell;

    switch (indexPath.row) {
        case kNameMainNumberCellIndexPath:
            cell = (ContactDetailCell*)[tableView dequeueReusableCellWithIdentifier:kNameMainNumberCell forIndexPath:indexPath];
            [self setUpNameMainUserCell:(ContactDetailCell*)cell];
            break;
        case kActionCellIndexPath:
            cell = (ActionContactDetailCell*)[tableView dequeueReusableCellWithIdentifier:kActionCell forIndexPath:indexPath];
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

#pragma mark - Utilities (Adaptable Cells)

-(NSUInteger)numberOfRowsForContact:(Contact*)contact
{
    NSUInteger numEmails = contact.emails.count;
    NSUInteger numPhoneNumbers = contact.userTextPhoneNumbers.count-1; //Don't count main
    
    return kMinRows + numEmails + numPhoneNumbers;
}

-(UITableViewCell*)adaptableCellAtIndexPath:(NSIndexPath*)idx
{
    NSInteger emailUpperBound = (NSInteger)(kFirstAdaptableCellRow+_contact.emails.count);
    NSInteger phoneNumberUpperBound = emailUpperBound + (NSInteger)_contact.userTextPhoneNumbers.count;
    
    
    ContactDetailCell * cell;
    
    if (idx.row > kFirstAdaptableCellRow && idx.row <= emailUpperBound)
    {
        cell = [self.tableView dequeueReusableCellWithIdentifier:kEmailCell forIndexPath:idx];
        
        cell.contactEmailLabel.text = [_contact.emails objectAtIndex:(NSUInteger)idx.row-_contact.emails.count];
        
        return cell;
    }
    
    else if (idx.row > emailUpperBound  && idx.row < phoneNumberUpperBound)
    {
        cell = [self.tableView dequeueReusableCellWithIdentifier:kAnnexPhoneNumberCell forIndexPath:idx];
        
        NSInteger i = idx.row - emailUpperBound ;
        
        cell.contactAnnexNumberLabel.text = [_contact.userTextPhoneNumbers objectAtIndex:(NSUInteger)i];
        
        return cell;
    }
    
    else if (idx.row == (NSInteger)[self numberOfRowsForContact:_contact]-1)
    {
        return [self.tableView dequeueReusableCellWithIdentifier:kNotesCell forIndexPath:idx];
        
    }
    
    else
    {
        NSLog(@"%s Problem at IndexPath %@", __PRETTY_FUNCTION__, idx);
        return nil;
    }
}

-(CGFloat)heightForAdaptableCellAtIndexPath:(NSIndexPath*)idx
{
    NSInteger emailUpperBound = (NSInteger)(kFirstAdaptableCellRow+_contact.emails.count);
    NSInteger phoneNumberUpperBound = emailUpperBound + (NSInteger)_contact.userTextPhoneNumbers.count;
    
    if (idx.row > kFirstAdaptableCellRow && idx.row <= emailUpperBound)
    {
        return kEmailCellHeight;
    }
    
    else if (idx.row > emailUpperBound && idx.row < phoneNumberUpperBound)
    {
        return kAnnexPhoneNumberCellHeight;
    }
    
    else if (idx.row == (NSInteger)[self numberOfRowsForContact:_contact]-1)
    {
        return kNotesCellHeight;
        
    }
    
    else
    {
        NSLog(@"%s Problem at IndexPath %@", __PRETTY_FUNCTION__, idx);
        return 44.0f;
    }
    
}


@end
