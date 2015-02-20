//
//  AdvancedSettingsTableViewController.m
//  Signal
//
//  Created by Dylan Bourgeois on 05/01/15.
//  Copyright (c) 2015 Open Whisper Systems. All rights reserved.
//

#import "AdvancedSettingsTableViewController.h"

#import <PastelogKit/Pastelog.h>
#import "Environment.h"
#import "PreferencesUtil.h"
#import "DebugLogger.h"


@interface AdvancedSettingsTableViewController ()

@property (strong, nonatomic) UITableViewCell * enableLogCell;
@property (strong, nonatomic) UITableViewCell * submitLogCell;

@property (strong, nonatomic) UISwitch * enableLogSwitch;
@end

@implementation AdvancedSettingsTableViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.navigationController.navigationBar setTranslucent:NO];    
    self.tableView.tableFooterView = [[UIView alloc]initWithFrame:CGRectZero];
}

-(instancetype)init {
    return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

-(void)loadView
{
    [super loadView];
    
    self.title = NSLocalizedString(@"SETTINGS_ADVANCED_TITLE", @"");
    
    //Enable Log
    self.enableLogCell = [[UITableViewCell alloc]init];
    self.enableLogCell.textLabel.text =  NSLocalizedString(@"SETTINGS_ADVANCED_DEBUGLOG", @"");
    self.enableLogCell.userInteractionEnabled = YES;
    
    self.enableLogSwitch = [[UISwitch alloc]initWithFrame:CGRectZero];
    [self.enableLogSwitch setOn:[Environment.preferences loggingIsEnabled]];
    [self.enableLogSwitch addTarget:self action:@selector(didToggleSwitch:) forControlEvents:UIControlEventTouchUpInside];
    
    self.enableLogCell.accessoryView = self.enableLogSwitch;
    
    
    //Send Log
    self.submitLogCell = [[UITableViewCell alloc]init];
    self.submitLogCell.textLabel.text = NSLocalizedString(@"SETTINGS_ADVANCED_SUBMIT_DEBUGLOG", @"");
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.enableLogSwitch.isOn ? 2 : 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return @"Logging";
}

-(UITableViewCell*)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    switch (indexPath.row) {
        case 0: return self.enableLogCell;
        case 1: return self.submitLogCell;
    }
    
    NSAssert(false, @"No Cell configured");
    
    return nil;
}

-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    if (indexPath.row == 1)
    {
        [Pastelog submitLogs];
    }
}

#pragma mark - Actions

-(void)didToggleSwitch:(UISwitch*)sender
{
    if (!sender.isOn) {
        [DebugLogger.sharedInstance wipeLogs];
        [DebugLogger.sharedInstance disableFileLogging];
    } else {
        [DebugLogger.sharedInstance enableFileLogging];
    }
    
    [Environment.preferences setLoggingEnabled:sender.isOn];
    [self.tableView reloadData];
}

@end
