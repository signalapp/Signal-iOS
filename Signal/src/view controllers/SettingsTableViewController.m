//
//  SettingsTableViewController.m
//  Signal
//
//  Created by Dylan Bourgeois on 03/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "SettingsTableViewController.h"

#define kProfileCellHeight  100.0f
#define kStandardCellHeight 44.0f

#define kNumberOfSections   3


typedef enum {
    kProfileRows  = 1,
    kSecurityRows = 5,
    kDebugRows    = 2,
} kRowsForSection;

typedef enum {
    kProfileSection,
    kSecuritySection,
    kDebugSection
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
        case kDebugSection:
            return kDebugRows;
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

@end
