#import <UIKit/UIKit.h>

#import "InboxFeedViewController.h"
#import "SettingsViewController.h"

#define BOTTOM_TAB_BAR_HEIGHT 64

@interface TabBarParentViewController : UIViewController

@property (strong, nonatomic) IBOutlet UIButton* tabBarFavouritesButton;
@property (strong, nonatomic) IBOutlet UIButton* tabBarInboxButton;
@property (strong, nonatomic) IBOutlet UIButton* tabBarContactsButton;
@property (strong, nonatomic) IBOutlet UIButton* tabBarDialerButton;
@property (strong, nonatomic) IBOutlet UIButton* tabBarCallLogButton;

@property (strong, nonatomic) IBOutlet UILabel* missedCallCountLabel;
@property (strong, nonatomic) IBOutlet UIImageView* whisperUserUpdateImageView;

@property (strong, nonatomic) IBOutlet UIView* viewControllerFrameView;
@property (strong, nonatomic) InboxFeedViewController* inboxFeedViewController;
@property (strong, nonatomic) SettingsViewController* settingsViewController;

- (IBAction)presentInboxViewController;
- (IBAction)presentDialerViewController;
- (IBAction)presentContactsViewController;
- (IBAction)presentFavouritesViewController;
- (IBAction)presentRecentCallsViewController;
- (void)presentInviteContactsViewController;

- (void)presentSettingsViewController;
- (void)updateMissedCallCountLabel;

- (void)setNewWhisperUsersAsSeen:(NSArray*)users;

- (void)showDialerViewControllerWithNumber:(PhoneNumber*)number;

@end
