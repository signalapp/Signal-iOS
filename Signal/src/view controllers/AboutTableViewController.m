//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <Social/Social.h>
#import "AboutTableViewController.h"
#import "UIUtil.h"
#import "UIViewController+OWS.h"

@interface AboutTableViewController ()

@property (strong, nonatomic) UITableViewCell *versionCell;
@property (strong, nonatomic) UITableViewCell *supportCell;
@property (strong, nonatomic) UITableViewCell *twitterInviteCell;

@property (strong, nonatomic) UILabel *versionLabel;

@property (strong, nonatomic) UILabel *footerView;

@end

typedef NS_ENUM(NSUInteger, AboutTableViewControllerSection) {
    AboutTableViewControllerSectionInformation,
    AboutTableViewControllerSectionHelp
};

@implementation AboutTableViewController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.navigationController.navigationBar setTranslucent:NO];
    [self useOWSBackButton];
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
}

- (void)loadView {
    [super loadView];

    self.title = NSLocalizedString(@"SETTINGS_ABOUT", @"Navbar title");

    // Version
    self.versionCell                = [[UITableViewCell alloc] init];
    self.versionCell.textLabel.text = NSLocalizedString(@"SETTINGS_VERSION", @"");

    self.versionLabel           = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 75, 30)];
    self.versionLabel.text      = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
    self.versionLabel.textColor = [UIColor lightGrayColor];
    self.versionLabel.font      = [UIFont ows_regularFontWithSize:16.0f];
    self.versionLabel.textAlignment = NSTextAlignmentRight;

    self.versionCell.accessoryView          = self.versionLabel;
    self.versionCell.userInteractionEnabled = NO;

    // Support
    self.supportCell                = [[UITableViewCell alloc] init];
    self.supportCell.textLabel.text = NSLocalizedString(@"SETTINGS_SUPPORT", @"");
    self.supportCell.accessoryType  = UITableViewCellAccessoryDisclosureIndicator;

    // Footer
    self.footerView               = [[UILabel alloc] init];
    self.footerView.text          = NSLocalizedString(@"SETTINGS_COPYRIGHT", @"");
    self.footerView.textColor     = [UIColor ows_darkGrayColor];
    self.footerView.font          = [UIFont ows_regularFontWithSize:15.0f];
    self.footerView.numberOfLines = 2;
    self.footerView.textAlignment = NSTextAlignmentCenter;
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case AboutTableViewControllerSectionInformation:
            return 1;
        case AboutTableViewControllerSectionHelp:
            return 1;
        default:
            return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case AboutTableViewControllerSectionInformation:
            return NSLocalizedString(@"SETTINGS_INFORMATION_HEADER", @"");
        case AboutTableViewControllerSectionHelp:
            return NSLocalizedString(@"SETTINGS_HELP_HEADER", @"");
        default:
            return nil;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    switch (indexPath.section) {
        case AboutTableViewControllerSectionInformation:
            return self.versionCell;
        case AboutTableViewControllerSectionHelp:
            return self.supportCell;
    }

    return nil;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    switch (indexPath.section) {
        case AboutTableViewControllerSectionHelp:
            [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"http://support.whispersystems.org"]];
            break;

        default:
            break;
    }
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    return section == AboutTableViewControllerSectionHelp ? self.footerView : nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    return section == AboutTableViewControllerSectionHelp ? 60.0f : 0;
}

@end
