//
//  SettingsTableViewController.m
//  Signal
//
//  Created by Dylan Bourgeois on 03/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "SettingsTableViewController.h"
#import "DJWActionSheet.h"
#import "SettingsTableViewCell.h"

#define kProfileCellHeight      87.0f
#define kStandardCellHeight     60.0f

#define kNumberOfSections       2

#define kClearHistoryLogCellRow 4
#define kSendDebugLogCellRow    6


typedef enum {
    kProfileRows  = 1,
    kSecurityRows = 7,
} kRowsForSection;

typedef enum {
    kProfileSection,
    kSecuritySection,
} kSection;

@interface SettingsTableViewController ()

@end

@implementation SettingsTableViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.tableView.tableFooterView = [[UIView alloc]initWithFrame:CGRectZero];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}


#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return kNumberOfSections;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    
    switch (section) {
        case kProfileSection:
            return kProfileRows;
            break;
        case kSecuritySection:
            return kSecurityRows;
            break;
        default:
            return 0;
            break;
    }
}

-(CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    switch (indexPath.section) {
        case kProfileSection:
            return kProfileCellHeight;
            break;
            
        default:
            return kStandardCellHeight;
            break;
    }
}

-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section==kSecuritySection)
    {
        switch (indexPath.row) {
            case kClearHistoryLogCellRow:
            {
                //Present more info
                [DJWActionSheet showInView:self.tabBarController.view
                                 withTitle:@"Are you sure you want to delete all your history ? This action cannot be reverted."
                         cancelButtonTitle:@"Cancel"
                    destructiveButtonTitle:nil
                         otherButtonTitles:@[@"I'm sure."]
                                  tapBlock:^(DJWActionSheet *actionSheet, NSInteger tappedButtonIndex) {
                                      [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
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
                
            case kSendDebugLogCellRow:
                //Send debug Log
                break;
            default:
                break;
        }
    }
}



@end
