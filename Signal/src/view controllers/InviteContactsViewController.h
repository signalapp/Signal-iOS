#import <UIKit/UIKit.h>
#import <MessageUI/MessageUI.h>
#import "SearchBarTitleView.h"

@interface InviteContactsViewController : UIViewController <UITableViewDelegate, UITableViewDataSource, UIActionSheetDelegate, SearchBarTitleViewDelegate>

@property (nonatomic, strong) IBOutlet UIView *unseenWhisperUsersHeaderView;
@property (nonatomic, strong) IBOutlet UIView *regularContactsHeaderView;
@property (nonatomic, strong) IBOutlet UITableView *contactTableView;

- (IBAction)dismissNewWhisperUsersTapped:(id)sender;

- (void)updateWithNewWhisperUsers:(NSArray *)users;

@end
