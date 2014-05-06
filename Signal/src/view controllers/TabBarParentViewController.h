#import <UIKit/UIKit.h>

#import "InboxFeedViewController.h"
#import "SettingsViewController.h"

#define BOTTOM_TAB_BAR_HEIGHT 64

@interface TabBarParentViewController : UIViewController

@property (nonatomic, strong) IBOutlet UIButton *tabBarFavouritesButton;
@property (nonatomic, strong) IBOutlet UIButton *tabBarInboxButton;
@property (nonatomic, strong) IBOutlet UIButton *tabBarContactsButton;
@property (nonatomic, strong) IBOutlet UIButton *tabBarDialerButton;
@property (nonatomic, strong) IBOutlet UIButton *tabBarCallLogButton;

@property (nonatomic, strong) IBOutlet UILabel *missedCallCountLabel;
@property (nonatomic, strong) IBOutlet UIImageView *whisperUserUpdateImageView;

@property (nonatomic, strong) IBOutlet UIView *viewControllerFrameView;
@property (nonatomic, strong) InboxFeedViewController *inboxFeedViewController;
@property (nonatomic, strong) SettingsViewController *settingsViewController;

- (IBAction)presentInboxViewController;
- (IBAction)presentDialerViewController;
- (IBAction)presentContactsViewController;
- (IBAction)presentFavouritesViewController;
- (IBAction)presentRecentCallsViewController;
- (void)presentInviteContactsViewController;

- (void)presentSettingsViewController;
- (void)updateMissedCallCountLabel;

- (void)setNewWhisperUsersAsSeen:(NSArray *)users;

- (void)showDialerViewControllerWithNumber:(PhoneNumber *)number;

@end
