#import <UIKit/UIKit.h>

#import "ContactsManager.h"
#import "InboxFeedTableViewCell.h"
#import "SearchBarTitleView.h"

/**
 *
 * InboxFeedViewController is the first view the user sees after they have registered
 * The search box searches items in your inbox, and contacts.
 * A tutorial is displayed if the user has never made a call.
 * This class is subscribed to the inbox feed table view cell delegate which tells us when to delete/archive items.
 *
 */

@interface InboxFeedViewController : UIViewController <UITableViewDelegate, UITableViewDataSource, InboxFeedTableViewCellDelegate, SearchBarTitleViewDelegate>

@property (strong, nonatomic) IBOutlet UITableView* inboxFeedTableView;
@property (strong, nonatomic) IBOutlet SearchBarTitleView* searchBarTitleView;
@property (strong, nonatomic) IBOutlet UIView* freshInboxView;
@property (strong, nonatomic) IBOutlet UILabel* freshAppTutorialTopLabel;
@property (strong, nonatomic) IBOutlet UILabel* freshAppTutorialMiddleLabel;



@end
