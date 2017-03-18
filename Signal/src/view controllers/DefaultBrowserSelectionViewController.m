//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "BrowserUtil.h"
#import "DefaultBrowserSelectionViewController.h"
#import "Environment.h"
#import "PropertyListPreferences.h"
#import "UIViewController+OWS.h"

@interface DefaultBrowserSelectionViewController ()

@property NSArray *options;

@end

@implementation DefaultBrowserSelectionViewController

- (void)viewDidLoad {
    self.options = [BrowserUtil detectInstalledBrowserNames];

    [super viewDidLoad];

    [self useOWSBackButton];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)[self.options count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
                                                   reuseIdentifier:@"DefaultBrowserOption"];
    PropertyListPreferences *prefs = [Environment preferences];
    NSString* browserName = self.options[(NSUInteger)indexPath.row];
    [[cell textLabel] setText:browserName];

    NSString *selectedBrowser = [prefs defaultBrowser];

    if ([selectedBrowser isEqualToString:browserName]) {
        cell.accessoryType = UITableViewCellAccessoryCheckmark;
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [Environment.preferences
        setDefaultBrowser:[self.options objectAtIndex:(NSUInteger) indexPath.row]];
    [self.navigationController popViewControllerAnimated:YES];
}

@end
