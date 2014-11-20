#import <UIKit/UIKit.h>
#import <MessageUI/MessageUI.h>
#import "SearchBarTitleView.h"

@interface InviteContactsViewController : UIViewController <UITableViewDelegate, UITableViewDataSource, UIActionSheetDelegate, SearchBarTitleViewDelegate>

@property (strong, nonatomic) IBOutlet UIView* unseenWhisperUsersHeaderView;
@property (strong, nonatomic) IBOutlet UIView* regularContactsHeaderView;
@property (strong, nonatomic) IBOutlet UITableView* contactTableView;

- (IBAction)dismissNewWhisperUsersTapped:(id)sender;

- (void)updateWithNewWhisperUsers:(NSArray*)users;

@end
