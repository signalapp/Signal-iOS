#import "LeftSideMenuViewController.h"
#import "LocalizableText.h"
#import "LeftSideMenuCell.h"
#import "UIUtil.h"

#import <UIViewController+MMDrawerController.h>

#define FIRST_SECTION_INDEX 0
#define SECOND_SECTION_INDEX 1

#define NUMBER_OF_TABLE_VIEW_SECTIONS 2

static NSString *SIDE_MENU_TABLE_CELL_IDENTIFIER = @"LeftSideMenuCell";
static NSString *WHISPER_SYSTEMS_URL = @"https://whispersystems.org/";
static NSString *WHISPER_SYSTEMS_BLOG_URL = @"https://whispersystems.org/blog";
static NSString *WHISPER_SYSTEMS_BUGREPORT_URL = @"http://support.whispersystems.org";

@interface LeftSideMenuViewController ()

@property (strong, nonatomic) NSArray* firstSectionOptions;
@property (strong, nonatomic) NSArray* secondSectionOptions;

@end

@implementation LeftSideMenuViewController

- (instancetype)initWithNibName:(NSString*)nibNameOrNil bundle:(NSBundle*)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        self.centerTabBarViewController = [[TabBarParentViewController alloc] init];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.firstSectionOptions = @[MAIN_MENU_OPTION_RECENT_CALLS,
                                 MAIN_MENU_OPTION_FAVOURITES,
                                 MAIN_MENU_OPTION_CONTACTS,
                                 MAIN_MENU_OPTION_DIALER,
                                 MAIN_MENU_INVITE_CONTACTS];

    self.secondSectionOptions = @[MAIN_MENU_OPTION_SETTINGS,
                                  MAIN_MENU_OPTION_ABOUT,
                                  MAIN_MENU_OPTION_REPORT_BUG,
                                  MAIN_MENU_OPTION_BLOG];

    self.mm_drawerController.closeDrawerGestureModeMask = MMCloseDrawerGestureModePanningCenterView | MMCloseDrawerGestureModeTapCenterView;
    self.mm_drawerController.openDrawerGestureModeMask = MMOpenDrawerGestureModeBezelPanningCenterView;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (BOOL)isLeftSideViewOpenCompletely {
    return self.mm_drawerController.visibleLeftDrawerWidth >= self.mm_drawerController.maximumLeftDrawerWidth;
}

#pragma mark - View Controller Presentation

- (void)showRecentsViewController {
    [self.centerTabBarViewController presentRecentCallsViewController];
    [self.mm_drawerController closeDrawerAnimated:YES completion:nil];
}

- (void)showContactsViewController {
    [self.centerTabBarViewController presentContactsViewController];
    [self.mm_drawerController closeDrawerAnimated:YES completion:nil];
}

- (void)showDialerViewController {
    [self.centerTabBarViewController presentDialerViewController];
    [self.mm_drawerController closeDrawerAnimated:YES completion:nil];
}

- (void)showSettingsViewController {
    [self.centerTabBarViewController presentSettingsViewController];
    [self.mm_drawerController closeDrawerAnimated:YES completion:nil];
}

- (void)showFavouritesViewController {
    [self.centerTabBarViewController presentFavouritesViewController];
    [self.mm_drawerController closeDrawerAnimated:YES completion:nil];
}

- (void)showInviteContactsViewController {
    [self.centerTabBarViewController presentInviteContactsViewController];
    [self.mm_drawerController closeDrawerAnimated:YES completion:nil];
}

- (void)selectMenuOption:(NSString*)menuOption {
    if ([menuOption isEqualToString:MAIN_MENU_OPTION_RECENT_CALLS]) {
        [self showRecentsViewController];
    }
    if ([menuOption isEqualToString:MAIN_MENU_OPTION_FAVOURITES]) {
        [self showFavouritesViewController];
    }
    if ([menuOption isEqualToString:MAIN_MENU_OPTION_CONTACTS]) {
        [self showContactsViewController];
    }
    if ([menuOption isEqualToString:MAIN_MENU_OPTION_DIALER]) {
        [self showDialerViewController];
    }
    if ([menuOption isEqualToString:MAIN_MENU_INVITE_CONTACTS]) {
        [self showInviteContactsViewController];
    }
    if ([menuOption isEqualToString:MAIN_MENU_OPTION_SETTINGS]) {
        [self showSettingsViewController];
    }
    if ([menuOption isEqualToString:MAIN_MENU_OPTION_ABOUT]) {
        [self openAboutWhisperUrl];
    }
    if ([menuOption isEqualToString:MAIN_MENU_OPTION_REPORT_BUG]) {
        [self openBugReporterUrl];
    }
    if ([menuOption isEqualToString:MAIN_MENU_OPTION_BLOG]) {
        [self openBlogUrl];
    }
}

- (void)openAboutWhisperUrl {
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:WHISPER_SYSTEMS_URL]];
}

- (void)openBugReporterUrl {
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:WHISPER_SYSTEMS_BUGREPORT_URL]];
}

- (void)openBlogUrl {
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:WHISPER_SYSTEMS_BLOG_URL]];
}

#pragma mark - UITableViewDelegate

- (CGFloat)tableView:(UITableView*)tableView heightForHeaderInSection:(NSInteger)section {
    if (section == FIRST_SECTION_INDEX) {
        return CGRectGetHeight(self.firstSectionHeaderView.frame);
    } else {
        return CGRectGetHeight(self.secondSectionHeaderView.frame);
    }
}

- (UIView*)tableView:(UITableView*)tableView viewForHeaderInSection:(NSInteger)section {
    if (section == FIRST_SECTION_INDEX) {
        return self.firstSectionHeaderView;
    } else {
        return self.secondSectionHeaderView;
    }
}

- (NSInteger)numberOfSectionsInTableView:(UITableView*)tableView {
    return NUMBER_OF_TABLE_VIEW_SECTIONS;
}

- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == FIRST_SECTION_INDEX) {
        return (NSInteger)self.firstSectionOptions.count;
    } else {
        return (NSInteger)self.secondSectionOptions.count;
    }
}

- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath {
    LeftSideMenuCell* cell = [tableView dequeueReusableCellWithIdentifier:SIDE_MENU_TABLE_CELL_IDENTIFIER];

    if (!cell) {
        cell = [[LeftSideMenuCell alloc] initWithStyle:UITableViewCellStyleDefault
                                       reuseIdentifier:SIDE_MENU_TABLE_CELL_IDENTIFIER];		
        cell.backgroundColor = [UIColor clearColor];
    }

    if (indexPath.section == FIRST_SECTION_INDEX) {
        cell.menuTitleLabel.text = self.firstSectionOptions[(NSUInteger)indexPath.row];
    } else {
        cell.menuTitleLabel.text = self.secondSectionOptions[(NSUInteger)indexPath.row];
    }

    return cell;
}

- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (self.isLeftSideViewOpenCompletely) {
        NSString* menuOption;
        if (indexPath.section == FIRST_SECTION_INDEX) {
            menuOption = self.firstSectionOptions[(NSUInteger)indexPath.row];
        } else {
            menuOption = self.secondSectionOptions[(NSUInteger)indexPath.row];
        }
        
        [self selectMenuOption:menuOption];
    }
}

@end
