//
//  NotificationSettingsOptionsViewController.m
//  Signal
//
//  Created by Frederic Jacobs on 24/04/15.
//  Copyright (c) 2015 Open Whisper Systems. All rights reserved.
//

#import "NotificationSettingsOptionsViewController.h"
#import "Environment.h"
#import "PropertyListPreferences.h"
#import "PreferencesUtil.h"

@interface NotificationSettingsOptionsViewController ()
@property NSArray *options;
@end

@implementation NotificationSettingsOptionsViewController

- (void)viewDidLoad
{
    self.options = @[@(NotificationNamePreview),
                     @(NotificationNameNoPreview),
                     @(NotificationNoNameNoPreview)];
    [super viewDidLoad];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return (NSInteger)[self.options count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [[UITableViewCell alloc]initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"NotificationSettingsOption"];
    PropertyListPreferences *prefs = [Environment preferences];
    [[cell textLabel] setText:[prefs nameForNotificationPreviewType:[[self.options objectAtIndex:(NSUInteger)indexPath.row] unsignedIntegerValue]]];
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [Environment.preferences setNotificationPreviewType:[[self.options objectAtIndex:(NSUInteger)indexPath.row] unsignedIntegerValue]];
    [self.navigationController popViewControllerAnimated:YES];
}

@end
