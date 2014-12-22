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
@property (nonatomic) NSIndexPath *defaultSelectedIndexPath;
@end

@implementation NotificationPreviewViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.navigationItem.title = @"Notification Style";
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
    self.clearsSelectionOnViewWillAppear = NO;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    NSInteger currentSetting = (NSInteger)[Environment.preferences notificationPreviewType];
    _defaultSelectedIndexPath = [NSIndexPath indexPathForRow:0 inSection:currentSetting + 1];
    [self selectRowAtIndexPath:_defaultSelectedIndexPath];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 4;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return 1;
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section
{
    UITableViewHeaderFooterView *header = (UITableViewHeaderFooterView *)view;
    [header.textLabel setTextColor:[UIColor blackColor]];
    if (SYSTEM_VERSION_GREATER_THAN(_iOS_8_0_2)) {
        [header.textLabel setFont:[UIFont ows_thinFontWithSize:14.0f]];
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (_defaultSelectedIndexPath != nil && ![_defaultSelectedIndexPath isEqual:indexPath]) {
        [self deselectRowAtIndexPath:_defaultSelectedIndexPath];
        _defaultSelectedIndexPath = nil;
    }

    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
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
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    cell.accessoryType = UITableViewCellAccessoryNone;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == 0) {
        return 120.0f;
    } else {
        return 80.0f;
    }
}

#pragma mark - Cell selection proxy

- (void)selectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [self.tableView.delegate tableView:self.tableView didSelectRowAtIndexPath:indexPath];
}

- (void)deselectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [self.tableView.delegate tableView:self.tableView didDeselectRowAtIndexPath:indexPath];
}

@end
