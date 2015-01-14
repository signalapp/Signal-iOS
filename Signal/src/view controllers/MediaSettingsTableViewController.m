//
//  MediaSettingsTableViewController.m
//  Signal
//
//  Created by Dylan Bourgeois on 05/01/15.
//  Copyright (c) 2015 Open Whisper Systems. All rights reserved.
//

#import "MediaSettingsTableViewController.h"

#import "Environment.h"
#import "PreferencesUtil.h"

@interface MediaSettingsTableViewController ()

@property (strong, nonatomic) UITableViewCell * uncroppedQualityCell;
@property (strong, nonatomic) UITableViewCell * highQualityCell;
@property (strong, nonatomic) UITableViewCell * averageQualityCell;
@property (strong, nonatomic) UITableViewCell * lowQualityCell;

@property (strong, nonatomic) NSIndexPath * lastIndexPath;

@end

@implementation MediaSettingsTableViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.navigationController.navigationBar setTranslucent:NO];
    self.tableView.tableFooterView = [[UIView alloc]initWithFrame:CGRectZero];
    [self showCheckmarkOnDefaultSetting:YES];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

-(instancetype)init
{
    return [super initWithStyle:UITableViewStyleGrouped];
}

-(void)loadView {
    [super loadView];
    
    self.title = @"Media";

    //Uncropped
    self.uncroppedQualityCell = [[UITableViewCell alloc]init];
    self.uncroppedQualityCell.textLabel.text = @"Uncropped";
    self.uncroppedQualityCell.selectionStyle = UITableViewCellSelectionStyleNone;
    
    //High
    self.highQualityCell = [[UITableViewCell alloc]init];
    self.highQualityCell.textLabel.text = @"High";
    self.highQualityCell.selectionStyle = UITableViewCellSelectionStyleNone;
    
    //Average
    self.averageQualityCell = [[UITableViewCell alloc]init];
    self.averageQualityCell.textLabel.text = @"Average";
    self.averageQualityCell.selectionStyle = UITableViewCellSelectionStyleNone;
    
    //Low
    self.lowQualityCell = [[UITableViewCell alloc]init];
    self.lowQualityCell.textLabel.text = @"Low";
    self.lowQualityCell.selectionStyle = UITableViewCellSelectionStyleNone;
    
}
#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 4;
}

-(UITableViewCell*)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    switch (indexPath.row) {
        case 0: return self.uncroppedQualityCell;
        case 1: return self.highQualityCell;
        case 2: return self.averageQualityCell;
        case 3: return self.lowQualityCell;
        default: return nil;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return @"Image upload quality";
}

-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [self showCheckmarkOnDefaultSetting:NO];
    [tableView cellForRowAtIndexPath:indexPath].accessoryType = UITableViewCellAccessoryCheckmark;
    [self updateSettingWithSelectedIndexPath:indexPath];
}

-(void)tableView:(UITableView *)tableView didDeselectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView cellForRowAtIndexPath:indexPath].accessoryType = UITableViewCellAccessoryNone;
}

#pragma mark - Setting

-(void)updateSettingWithSelectedIndexPath:(NSIndexPath*)indexPath
{
    switch (indexPath.row) {
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
            break;
    }
}

-(NSIndexPath*)indexPathForSetting:(TSImageQuality)setting
{
    switch (setting) {
        case TSImageQualityUncropped: return [NSIndexPath indexPathForRow:0 inSection:0];
        case TSImageQualityHigh: return [NSIndexPath indexPathForRow:1 inSection:0];
        case TSImageQualityMedium: return [NSIndexPath indexPathForRow:2 inSection:0];
        case TSImageQualityLow: return [NSIndexPath indexPathForRow:3 inSection:0];
    }
}

-(void)showCheckmarkOnDefaultSetting:(BOOL)show
{
    NSIndexPath * defaultIndexPath = [self indexPathForSetting:[Environment.preferences imageUploadQuality]];
    [self.tableView cellForRowAtIndexPath:defaultIndexPath].accessoryType = show ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
}

@end
