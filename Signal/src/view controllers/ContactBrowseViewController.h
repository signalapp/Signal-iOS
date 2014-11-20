#import <UIKit/UIKit.h>
#import "SearchBarTitleView.h"

/**
 *
 * ContactBrowseViewController displays contacts from ContactsManager inside of a table view.
 * This class subscibes to addressbook updates to refresh information and/or add new contacts.
 *
 */

@interface ContactBrowseViewController : UIViewController <UITableViewDataSource, UITableViewDelegate, SearchBarTitleViewDelegate>

@property (strong, nonatomic) IBOutlet UITableView* contactTableView;
@property (strong, nonatomic) IBOutlet SearchBarTitleView* searchBarTitleView;
@property (strong, nonatomic) IBOutlet UIView* notificationView;
@property (strong, nonatomic) UIRefreshControl* refreshControl;

- (IBAction)notificationViewTapped:(id)sender;
- (void)showNotificationForNewWhisperUsers:(NSArray*)users;

@end
