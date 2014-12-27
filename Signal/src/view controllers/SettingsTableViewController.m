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

#import "TSAccountManager.h"
#import "TSStorageManager.h"
#import "Environment.h"
#import "PreferencesUtil.h"
#import "RPServerRequestsManager.h"

#import <PastelogKit/Pastelog.h>

#define kProfileCellHeight      87.0f
#define kStandardCellHeight     60.0f

#define kNumberOfSections       2

#define kMessageDisplayCellRow  1
#define kImageQualitySettingRow 2
#define kClearHistoryLogCellRow 3
#define kSendDebugLogCellRow    5
#define kUnregisterCell         6


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
    self.registeredNumber.text     = [TSAccountManager registeredNumber];
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
                                 withTitle:@"Are you sure you want to delete all your history (messages, attachments, call history ...)? This action cannot be reverted."
                         cancelButtonTitle:@"Cancel"
                    destructiveButtonTitle:@"I'm sure."
                         otherButtonTitles:@[]
                                  tapBlock:^(DJWActionSheet *actionSheet, NSInteger tappedButtonIndex) {
                                      [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
                                      if (tappedButtonIndex == actionSheet.cancelButtonIndex) {
                                          NSLog(@"User Cancelled");
                                          
                                      } else if (tappedButtonIndex == actionSheet.destructiveButtonIndex){
                                          [[TSStorageManager sharedManager] deleteThreadsAndMessages];
                                      } else {
                                          NSLog(@"The user tapped button at index: %li", (long)tappedButtonIndex);
                                      }
                                  }];
                
                break;
            }
            
            case kImageQualitySettingRow:
            {
                [DJWActionSheet showInView:self.tabBarController.view
                                 withTitle:nil
                         cancelButtonTitle:@"Cancel"
                    destructiveButtonTitle:nil
                         otherButtonTitles:@[@"Uncompressed", @"High", @"Medium", @"Low"]
                                  tapBlock:^(DJWActionSheet *actionSheet, NSInteger tappedButtonIndex) {
                                      [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
                                      if (tappedButtonIndex == actionSheet.cancelButtonIndex) {
                                          DDLogVerbose(@"User Cancelled <%s>", __PRETTY_FUNCTION__);
                                          
                                      } else if (tappedButtonIndex == actionSheet.destructiveButtonIndex) {
                                          DDLogVerbose(@"Destructive button tapped <%s>", __PRETTY_FUNCTION__);
                                      }else {
                                          switch (tappedButtonIndex) {
                                              case 0:
                                                  [Environment.preferences setImageUploadQuality:TSImageQualityUncropped];
                                                  break;
                                              case 1:
                                                  [Environment.preferences setImageUploadQuality:TSImageQualityHigh];
                                                  break;
                                              case 2:
                                                  [Environment.preferences setImageUploadQuality:TSImageQualityMedium];
                                                  break;
                                              case 3:
                                                  [Environment.preferences setImageUploadQuality:TSImageQualityLow];
                                                  break;
                                              default:
                                                  DDLogWarn(@"Illegal Image Quality Tapped in <%s>", __PRETTY_FUNCTION__);
                                                  break;
                                          }
                                          
                                          SettingsTableViewCell * cell = (SettingsTableViewCell*)[tableView cellForRowAtIndexPath:indexPath];
                                          [cell updateImageQualityLabel];
                                      }
                                  }];
                break;
            }
                
            case kSendDebugLogCellRow:
                [Pastelog submitLogs];
                break;
                
            case kUnregisterCell:
                [TSAccountManager unregisterTextSecureWithSuccess:^{
                    [[TSStorageManager sharedManager] wipe];
                    exit(0);
                } failure:^(NSError *error) {
                    SignalAlertView(@"Failed to unregister", @"");
                }];
                break;
                
            default:
                break;
        }
    }
}

@end
