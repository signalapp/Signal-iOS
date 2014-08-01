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

@property (nonatomic, strong) IBOutlet UITableView *inboxFeedTableView;
@property (nonatomic, strong) IBOutlet SearchBarTitleView *searchBarTitleView;
@property (nonatomic, strong) IBOutlet UIView *freshInboxView;
@property (nonatomic, strong) IBOutlet UILabel *freshAppTutorialTopLabel;
@property (nonatomic, strong) IBOutlet UILabel *freshAppTutorialMiddleLabel;



@end
