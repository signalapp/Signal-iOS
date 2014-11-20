#import "AppAudioManager.h"
#import "CallLogViewController.h"
#import "ContactBrowseViewController.h"
#import "DialerViewController.h"
#import "Environment.h"
#import "FavouritesViewController.h"
#import "InviteContactsViewController.h"
#import "NotificationManifest.h"
#import "RecentCallManager.h"
#import "RegisterViewController.h"
#import "TabBarParentViewController.h"

#import <UIViewController+MMDrawerController.h>

@interface TabBarParentViewController ()

@property (strong, nonatomic) DialerViewController* dialerViewController;
@property (strong, nonatomic) ContactBrowseViewController* contactsViewController;
@property (strong, nonatomic) CallLogViewController* callLogViewController;
@property (strong, nonatomic) FavouritesViewController* favouritesViewController;
@property (strong, nonatomic) InviteContactsViewController* inviteContactsViewController;

@property (strong, nonatomic) UINavigationController* contactNavigationController;
@property (strong, nonatomic) UINavigationController* dialerNavigationController;
@property (strong, nonatomic) UINavigationController* callLogNavigationController;
@property (strong, nonatomic) UINavigationController* inboxFeedNavigationController;
@property (strong, nonatomic) UINavigationController* favouritesNavigationController;
@property (strong, nonatomic) UINavigationController* settingsNavigationController;
@property (strong, nonatomic) UINavigationController* inviteContactsNavigationController;

@property (strong, nonatomic) UIViewController* currentViewController;

@end

@implementation TabBarParentViewController

- (instancetype)init {
    if (self = [super init]) {
        self.settingsViewController             = [[SettingsViewController alloc] init];
        self.inboxFeedViewController            = [[InboxFeedViewController alloc] init];
        self.settingsNavigationController       = [[UINavigationController alloc] initWithRootViewController:self.settingsViewController];
        self.inviteContactsViewController       = [[InviteContactsViewController alloc] init];
        self.inviteContactsNavigationController = [[UINavigationController alloc] initWithRootViewController:self.inviteContactsViewController];
        self.contactsViewController             = [[ContactBrowseViewController alloc] init];
        self.contactNavigationController        = [[UINavigationController alloc] initWithRootViewController:self.contactsViewController];
    }
    
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self updateMissedCallCountLabel];
    if (!self.currentViewController) {
        [self presentInboxViewController];
    }
    self.whisperUserUpdateImageView.hidden = [self hideUserUpdateNotification];
    
    ObservableValue* recentCallObservable = Environment.getCurrent.recentCallManager.getObservableRecentCalls;
    [recentCallObservable watchLatestValue:^(NSArray* latestRecents) {
        [self updateMissedCallCountLabel];		
    } onThread:NSThread.mainThread untilCancelled:nil];
    
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(newUsersDetected:)
                                               name:NOTIFICATION_NEW_USERS_AVAILABLE
                                             object:nil];

}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return self.currentViewController == self.dialerNavigationController ? UIStatusBarStyleDefault: UIStatusBarStyleLightContent;
}

- (void)presentChildViewController:(UIViewController*)controller {
    [self removeCurrentChildViewController];
    self.currentViewController = controller;
    [self addChildViewController:controller];
    controller.view.frame = self.viewControllerFrameView.frame;
    [self.viewControllerFrameView addSubview:controller.view];
    [controller didMoveToParentViewController:self];
    [self setNeedsStatusBarAppearanceUpdate];

    self.tabBarFavouritesButton.backgroundColor = UIUtil.darkBackgroundColor;
    self.tabBarContactsButton.backgroundColor   = UIUtil.darkBackgroundColor;
    self.tabBarDialerButton.backgroundColor     = UIUtil.darkBackgroundColor;
    self.tabBarInboxButton.backgroundColor      = UIUtil.darkBackgroundColor;
    self.tabBarCallLogButton.backgroundColor    = UIUtil.darkBackgroundColor;
}

- (void)removeCurrentChildViewController {
    if (self.currentViewController) {
        [self.currentViewController willMoveToParentViewController:nil];
        [self.currentViewController.view removeFromSuperview];
        [self.currentViewController removeFromParentViewController];
    }
}

- (void)presentInboxViewController {
    if (!self.inboxFeedNavigationController) {
        self.inboxFeedNavigationController = [[UINavigationController alloc] initWithRootViewController:self.inboxFeedViewController];
    }

    if (self.currentViewController == self.inboxFeedNavigationController) {
        [self.inboxFeedNavigationController popToRootViewControllerAnimated:YES];
    } else {
        [self presentChildViewController:self.inboxFeedNavigationController];
        self.tabBarInboxButton.backgroundColor = UIColor.darkGrayColor;
    }
}

- (IBAction)presentDialerViewController {
    [self showDialerViewControllerWithNumber:nil];
}

- (void)presentContactsViewController {
    [self.contactNavigationController popToRootViewControllerAnimated:NO];
    [self presentChildViewController:self.contactNavigationController];
    self.tabBarContactsButton.backgroundColor = UIColor.darkGrayColor;
}

- (void)presentRecentCallsViewController {
    if (!self.callLogViewController) {
        self.callLogNavigationController = [[UINavigationController alloc] initWithRootViewController:[[CallLogViewController alloc] init]];
    }

    [self presentChildViewController:self.callLogNavigationController];
    self.tabBarCallLogButton.backgroundColor = UIColor.darkGrayColor;
}

- (void)presentFavouritesViewController {
    if (!self.favouritesViewController) {
        self.favouritesNavigationController = [[UINavigationController alloc] initWithRootViewController:[[FavouritesViewController alloc] init]];
    }

    [self.favouritesNavigationController popToRootViewControllerAnimated:NO];
    [self presentChildViewController:self.favouritesNavigationController];
    self.tabBarFavouritesButton.backgroundColor = UIColor.darkGrayColor;
}

- (void)presentInviteContactsViewController {
    [self.inviteContactsNavigationController popToRootViewControllerAnimated:NO];
    [self presentChildViewController:self.inviteContactsNavigationController];
}

- (void)presentSettingsViewController {
    [self presentChildViewController:self.settingsNavigationController];
}

- (void)presentLeftSideMenu {
    [self.mm_drawerController toggleDrawerSide:MMDrawerSideLeft animated:YES completion:nil];
}

- (void)showDialerViewControllerWithNumber:(PhoneNumber*)number {
    if (!self.dialerViewController) {
        self.dialerNavigationController = [[UINavigationController alloc] initWithRootViewController:[[DialerViewController alloc] init]];
    }
    if (number) {
        self.dialerViewController.phoneNumber = number;
    }
    [self.dialerNavigationController popToRootViewControllerAnimated:NO];
    [self presentChildViewController:self.dialerNavigationController];
    self.tabBarDialerButton.backgroundColor = UIColor.darkGrayColor;
}

- (void)updateMissedCallCountLabel {
    NSUInteger missedCallCount = Environment.getCurrent.recentCallManager.missedCallCount;
    if (missedCallCount > 0) {
        self.tabBarInboxButton.frame = CGRectMake(CGRectGetMinX(self.tabBarInboxButton.frame),
                                                  CGRectGetMinY(self.tabBarInboxButton.frame),
                                                  CGRectGetWidth(self.tabBarInboxButton.frame),
                                                  CGRectGetHeight(self.tabBarInboxButton.frame) -
                                                  CGRectGetHeight(self.missedCallCountLabel.frame));
        self.missedCallCountLabel.text = [NSString stringWithFormat:@"%lu",(unsigned long)missedCallCount];
        self.missedCallCountLabel.hidden = NO;
    } else {
        self.tabBarInboxButton.frame = CGRectMake(CGRectGetMinX(self.tabBarInboxButton.frame),
                                                  CGRectGetMinY(self.tabBarInboxButton.frame),
                                                  CGRectGetWidth(self.tabBarInboxButton.frame),
                                                  CGRectGetHeight(self.tabBarInboxButton.frame));
        self.missedCallCountLabel.hidden = YES;
    }
}

#pragma mark - Contact Updates

- (void)newUsersDetected:(NSNotification*)notification {
    dispatch_async( dispatch_get_main_queue(), ^{
        NSArray* newUsers = [notification userInfo][NOTIFICATION_DATAKEY_NEW_USERS];
        [self updateNewUsers:newUsers];
    });
}

- (void)updateNewUsers:(NSArray*)users {
    [self.inviteContactsViewController updateWithNewWhisperUsers:users];
    [self.contactsViewController showNotificationForNewWhisperUsers:users];
    self.whisperUserUpdateImageView.hidden = [self hideUserUpdateNotification];
}

- (void)setNewWhisperUsersAsSeen:(NSArray*)users {
    [Environment.getCurrent.contactsManager addContactsToKnownWhisperUsers:users];
    [self.contactsViewController showNotificationForNewWhisperUsers:nil];
    self.whisperUserUpdateImageView.hidden = [self hideUserUpdateNotification];
  }

- (BOOL)hideUserUpdateNotification {
    return (0 == Environment.getCurrent.contactsManager.getNumberOfUnacknowledgedCurrentUsers);
}
@end
