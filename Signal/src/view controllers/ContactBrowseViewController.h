#import <UIKit/UIKit.h>
#import "SearchBarTitleView.h"

/**
 *
 * ContactBrowseViewController displays contacts from ContactsManager inside of a table view.
 * This class subscibes to addressbook updates to refresh information and/or add new contacts.
 *
 */

@interface ContactBrowseViewController : UIViewController <UITableViewDataSource, UITableViewDelegate, SearchBarTitleViewDelegate>

@property (nonatomic, strong) IBOutlet UITableView *contactTableView;
@property (nonatomic, strong) IBOutlet SearchBarTitleView *searchBarTitleView;
@property (nonatomic, strong) IBOutlet UIView *notificationView;
@property (nonatomic, retain) UIRefreshControl *refreshControl;
@property (nonatomic) NSTimer *refreshTimer;

- (IBAction)notificationViewTapped:(id)sender;
- (void)showNotificationForNewWhisperUsers:(NSArray *)users;

@end
