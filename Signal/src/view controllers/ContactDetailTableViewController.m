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


typedef enum {
    kNameMainNumberCellIndexPath   = 0,
    kActionCellIndexPath           = 1,
    kShareCellIndexPath            = 2,
    kEmailCellIndexPath            = 3,
    kAnnexPhoneNumberCellIndexPath = 4,
    kNotesCellIndexPath            = 5,
} kCellIndexPath;

typedef enum {
    kNameMainNumberCellHeight      = 180,
    kActionCellHeight              = 60,
    kShareCellHeight               = 60,
    kEmailCellHeight               = 60,
    kAnnexPhoneNumberCellHeight    = 60,
    kNotesCellHeight               = 165,
} kCellHeight;

static NSString* const kNameMainNumberCell = @"NameMainNumberCell";
static NSString* const kActionCell         = @"ActionCell";

//Deprecated
static NSString* const kShareCell    = @"ShareCell";
static NSString* const kEmailCell   = @"EmailCell";
static NSString* const kAnnexPhoneNumberCell      = @"AnnexPhoneNumberCell";
static NSString *const kNotesCell = @"NotesCell";
//

static NSString *const kContactDetailSegue = @"DetailSegue";



@interface ContactDetailTableViewController ()

@end

@implementation ContactDetailTableViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
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
    return 6;
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
        case kEmailCellIndexPath:
            cell = [tableView dequeueReusableCellWithIdentifier:kEmailCell forIndexPath:indexPath];
            break;
        case kAnnexPhoneNumberCellIndexPath:
            cell = [tableView dequeueReusableCellWithIdentifier:kAnnexPhoneNumberCell forIndexPath:indexPath];
            break;
        case kNotesCellIndexPath:
            cell = [tableView dequeueReusableCellWithIdentifier:kNotesCell forIndexPath:indexPath];
            break;
            
        default:
            break;
    }
    
    return cell;
}


-(void)setUpNameMainUserCell:(ContactDetailCell*)cell
{
    Contact* c = self.contact;
    
    cell.contactName.text = [c fullName];
    
    cell.contactPhoneNumber.text = [[c parsedPhoneNumbers] firstObject];
    
    if (c.image) {
        cell.contactImageView.image = c.image;
    }
    [cell.contactImageView.layer setCornerRadius:50.0f];
    [cell.contactImageView.layer setMasksToBounds:YES];

    
}

-(CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    CGFloat cellHeight = 44.0f;
    
    switch (indexPath.row) {
        case kNameMainNumberCellIndexPath:
            cellHeight = kNameMainNumberCellHeight;
            break;
        case kActionCellIndexPath:
            cellHeight = kActionCellHeight;
            break;
        case kShareCellIndexPath:
            cellHeight = kShareCellHeight;
            break;
        case kEmailCellIndexPath:
            cellHeight = kEmailCellHeight;
            break;
        case kAnnexPhoneNumberCellIndexPath:
            cellHeight = kAnnexPhoneNumberCellHeight;
            break;
        case kNotesCellIndexPath:
            cellHeight = kNotesCellHeight;
            break;
        default:
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

@end
