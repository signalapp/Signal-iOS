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

@interface TabBarParentViewController () {
    DialerViewController *_dialerViewController;
    ContactBrowseViewController *_contactsViewController;
    CallLogViewController *_callLogViewController;
    FavouritesViewController *_favouritesViewController;
    InviteContactsViewController *_inviteContactsViewController;
    
    UINavigationController *_contactNavigationController;
    UINavigationController *_dialerNavigationController;
    UINavigationController *_callLogNavigationController;
    UINavigationController *_inboxFeedNavigationController;
    UINavigationController *_favouritesNavigationController;
    UINavigationController *_settingsNavigationController;
    UINavigationController *_inviteContactsNavigationController;
    
    UIViewController *_currentViewController;
}

@end

@implementation TabBarParentViewController

- (id)init {
    if ((self = [super init])) {
        _settingsViewController = [SettingsViewController new];
        _inboxFeedViewController = [InboxFeedViewController new];
        _settingsNavigationController = [[UINavigationController alloc] initWithRootViewController:_settingsViewController];
        _inviteContactsViewController = [InviteContactsViewController new];
        _inviteContactsNavigationController = [[UINavigationController alloc] initWithRootViewController:_inviteContactsViewController];
        _contactsViewController = [ContactBrowseViewController new];
        _contactNavigationController = [[UINavigationController alloc] initWithRootViewController:_contactsViewController];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self updateMissedCallCountLabel];
    if (!_currentViewController) {
        [self presentInboxViewController];
    }
    _whisperUserUpdateImageView.hidden = [self hideUserUpdateNotification];
    
    ObservableValue *recentCallObservable = [[[Environment getCurrent] recentCallManager] getObservableRecentCalls];
    [recentCallObservable watchLatestValue:^(NSArray *latestRecents) {
        [self updateMissedCallCountLabel];		
    } onThread:[NSThread mainThread] untilCancelled:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(newUsersDetected:)
                                                 name:NOTIFICATION_NEW_USERS_AVAILABLE
                                               object:nil];

}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return _currentViewController == _dialerNavigationController ? UIStatusBarStyleDefault: UIStatusBarStyleLightContent;
}

- (void)presentChildViewController:(UIViewController *)controller {
    [self removeCurrentChildViewController];
    _currentViewController = controller;
    [self addChildViewController:controller];
    controller.view.frame = _viewControllerFrameView.frame;
    [_viewControllerFrameView addSubview:controller.view];
    [controller didMoveToParentViewController:self];
    [self setNeedsStatusBarAppearanceUpdate];

    _tabBarFavouritesButton.backgroundColor = [UIUtil darkBackgroundColor];
    _tabBarContactsButton.backgroundColor = [UIUtil darkBackgroundColor];
    _tabBarDialerButton.backgroundColor = [UIUtil darkBackgroundColor];
    _tabBarInboxButton.backgroundColor = [UIUtil darkBackgroundColor];
    _tabBarCallLogButton.backgroundColor = [UIUtil darkBackgroundColor];
}

- (void)removeCurrentChildViewController {
    if (_currentViewController) {
        [_currentViewController willMoveToParentViewController:nil];
        [_currentViewController.view removeFromSuperview];
        [_currentViewController removeFromParentViewController];
    }
}

- (void)presentInboxViewController {
    if (!_inboxFeedNavigationController) {
        _inboxFeedNavigationController = [[UINavigationController alloc] initWithRootViewController:_inboxFeedViewController];
    }

    if (_currentViewController == _inboxFeedNavigationController) {
        [_inboxFeedNavigationController popToRootViewControllerAnimated:YES];
    } else {
        [self presentChildViewController:_inboxFeedNavigationController];
        _tabBarInboxButton.backgroundColor = [UIColor darkGrayColor];
    }
}

- (IBAction)presentDialerViewController {
    [self showDialerViewControllerWithNumber:nil];
}

- (void)presentContactsViewController {
    [_contactNavigationController popToRootViewControllerAnimated:NO];
    [self presentChildViewController:_contactNavigationController];
    _tabBarContactsButton.backgroundColor = [UIColor darkGrayColor];
}

- (void)presentRecentCallsViewController {
    if (!_callLogViewController) {
        _callLogViewController = [CallLogViewController new];
        _callLogNavigationController = [[UINavigationController alloc] initWithRootViewController:_callLogViewController];
    }

    [self presentChildViewController:_callLogNavigationController];
    _tabBarCallLogButton.backgroundColor = [UIColor darkGrayColor];
}

- (void)presentFavouritesViewController {
    if (!_favouritesViewController) {
        _favouritesViewController = [FavouritesViewController new];
        _favouritesNavigationController = [[UINavigationController alloc] initWithRootViewController:_favouritesViewController];
    }

    [_favouritesNavigationController popToRootViewControllerAnimated:NO];
    [self presentChildViewController:_favouritesNavigationController];
    _tabBarFavouritesButton.backgroundColor = [UIColor darkGrayColor];
}

- (void)presentInviteContactsViewController {
    [_inviteContactsNavigationController popToRootViewControllerAnimated:NO];
    [self presentChildViewController:_inviteContactsNavigationController];
}

- (void)presentSettingsViewController {
    [self presentChildViewController:_settingsNavigationController];
}

- (void)presentLeftSideMenu {
    [self.mm_drawerController toggleDrawerSide:MMDrawerSideLeft animated:YES completion:nil];
}

- (void)showDialerViewControllerWithNumber:(PhoneNumber *)number {
    if (!_dialerViewController) {
        _dialerViewController = [DialerViewController new];
        _dialerNavigationController = [[UINavigationController alloc] initWithRootViewController:_dialerViewController];
    }
    if (number) {
        _dialerViewController.phoneNumber = number;
    }
    [_dialerNavigationController popToRootViewControllerAnimated:NO];
    [self presentChildViewController:_dialerNavigationController];
    _tabBarDialerButton.backgroundColor = [UIColor darkGrayColor];
}

- (void)updateMissedCallCountLabel {
    NSUInteger missedCallCount = [[[Environment getCurrent] recentCallManager] missedCallCount];
    if (missedCallCount > 0) {
        _tabBarInboxButton.frame = CGRectMake(CGRectGetMinX(_tabBarInboxButton.frame),
                                              CGRectGetMinY(_tabBarInboxButton.frame),
                                              CGRectGetWidth(_tabBarInboxButton.frame),
                                              CGRectGetHeight(_tabBarInboxButton.frame) - CGRectGetHeight(_missedCallCountLabel.frame));
        _missedCallCountLabel.text = [NSString stringWithFormat:@"%lu",(unsigned long)missedCallCount];
        _missedCallCountLabel.hidden = NO;
    } else {
        _tabBarInboxButton.frame = CGRectMake(CGRectGetMinX(_tabBarInboxButton.frame),
                                              CGRectGetMinY(_tabBarInboxButton.frame),
                                              CGRectGetWidth(_tabBarInboxButton.frame),
                                              CGRectGetHeight(_tabBarInboxButton.frame));
        _missedCallCountLabel.hidden = YES;
    }
}

#pragma mark - Contact Updates

- (void)newUsersDetected:(NSNotification* )notification {
    dispatch_async( dispatch_get_main_queue(), ^{
        NSArray *newUsers = [notification userInfo][NOTIFICATION_DATAKEY_NEW_USERS];
        [self updateNewUsers:newUsers];
    });
}

- (void)updateNewUsers:(NSArray *)users {
    [_inviteContactsViewController updateWithNewWhisperUsers:users];
    [_contactsViewController showNotificationForNewWhisperUsers:users];
    _whisperUserUpdateImageView.hidden = [self hideUserUpdateNotification];
}

- (void)setNewWhisperUsersAsSeen:(NSArray *)users {
    [[[Environment getCurrent] contactsManager] addContactsToKnownWhisperUsers:users];
    [_contactsViewController showNotificationForNewWhisperUsers:nil];
    _whisperUserUpdateImageView.hidden = [self hideUserUpdateNotification];
  }

-(BOOL) hideUserUpdateNotification {
    return (0 == [[[Environment getCurrent] contactsManager] getNumberOfUnacknowledgedCurrentUsers]);
}
@end
