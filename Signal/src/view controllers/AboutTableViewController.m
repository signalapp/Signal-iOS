//
//  AboutTableViewController.m
//  Signal
//
//  Created by Dylan Bourgeois on 05/01/15.
//  Copyright (c) 2015 Open Whisper Systems. All rights reserved.
//

#import <Social/Social.h>
#import "AboutTableViewController.h"
#import "UIUtil.h"

@interface AboutTableViewController ()

@property (strong, nonatomic) UITableViewCell *versionCell;
@property (strong, nonatomic) UITableViewCell *supportCell;
@property (strong, nonatomic) UITableViewCell *twitterInviteCell;

@property (strong, nonatomic) UILabel *versionLabel;

@property (strong, nonatomic) UILabel *footerView;

@end

@implementation AboutTableViewController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.navigationController.navigationBar setTranslucent:NO];
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
}

- (void)loadView {
    [super loadView];

    self.title = NSLocalizedString(@"SETTINGS_ABOUT", @"");

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


    // Twitter Invite
    self.twitterInviteCell                = [[UITableViewCell alloc] init];
    self.twitterInviteCell.textLabel.text = NSLocalizedString(@"SETTINGS_SHARE_INSTALL", @"");

    UIImageView *twitterImageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"twitter_logo"]];
    [twitterImageView setFrame:CGRectMake(0, 0, 34, 34)];
    twitterImageView.contentMode = UIViewContentModeScaleAspectFit;

    self.twitterInviteCell.accessoryView = twitterImageView;
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0:
            return 1;
        case 1:
            return 1;
        case 2:
            return 1;
        default:
            return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0:
            return NSLocalizedString(@"SETTINGS_INFORMATION_HEADER", @"");
        case 1:
            return NSLocalizedString(@"SETTINGS_INVITE_HEADER", @"");
        case 2:
            return NSLocalizedString(@"SETTINGS_HELP_HEADER", @"");

        default:
            return nil;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    switch (indexPath.section) {
        case 0:
            return self.versionCell;
        case 1:
            return self.twitterInviteCell;
        case 2:
            return self.supportCell;
    }

    return nil;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    switch (indexPath.section) {
        case 1:
            [self tappedInviteTwitter];
            break;
        case 2:
            [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"http://support.whispersystems.org"]];
            break;

        default:
            break;
    }
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    return section == 2 ? self.footerView : nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    return section == 2 ? 60.0f : 0;
}

- (void)tappedInviteTwitter {
    if ([SLComposeViewController isAvailableForServiceType:SLServiceTypeTwitter]) {
        SLComposeViewController *tweetSheet =
            [SLComposeViewController composeViewControllerForServiceType:SLServiceTypeTwitter];

        NSString *tweetString = [NSString stringWithFormat:NSLocalizedString(@"SETTINGS_INVITE_TWITTER_TEXT", @"")];
        [tweetSheet setInitialText:tweetString];
        [tweetSheet addURL:[NSURL URLWithString:@"https://whispersystems.org/signal/install/"]];
        tweetSheet.completionHandler = ^(SLComposeViewControllerResult result) {
        };
        [self presentViewController:tweetSheet animated:YES completion:[UIUtil modalCompletionBlock]];
    }
}

@end
