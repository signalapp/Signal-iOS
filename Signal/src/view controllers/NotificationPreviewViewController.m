//
//  NotificationPreviewViewController.m
//  Signal
//
//  Created by Dylan Bourgeois on 09/12/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "NotificationPreviewViewController.h"
#import "UIUtil.h"

#import "PreferencesUtil.h"
#import "Environment.h"

@interface NotificationPreviewViewController ()

@end

@implementation NotificationPreviewViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.title = @"Notification Style";
    self.tableView.tableFooterView = [[UIView alloc]initWithFrame:CGRectZero];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 4;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 1;
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section
{
    UITableViewHeaderFooterView *header = (UITableViewHeaderFooterView *)view;
    [header.textLabel setTextColor:[UIColor blackColor]];
    [header.textLabel setFont:[UIFont ows_thinFontWithSize:14.0f]];
    
}

-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell * cell = [tableView cellForRowAtIndexPath:indexPath];
    cell.accessoryType = UITableViewCellAccessoryCheckmark;
    
    switch (indexPath.section) {
        case 1:
            [Environment.preferences setNotificationPreviewType:NotificationNoNameNoPreview];
            break;
            
        case 2:
            [Environment.preferences setNotificationPreviewType:NotificationNameNoPreview];
            break;
            
        case 3:
            [Environment.preferences setNotificationPreviewType:NotificationNamePreview];
            break;
            
        default:
            break;
    }
}

- (void)tableView:(UITableView *)tableView didDeselectRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell * cell = [tableView cellForRowAtIndexPath:indexPath];
    
    cell.accessoryType = UITableViewCellAccessoryNone;
}

-(CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == 0) {
        return 120.0f;
    } else {
        return 80.0f;
    }
}




@end
