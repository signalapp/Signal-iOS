#import <UIKit/UIKit.h>


@interface ViewController : UIViewController <UITableViewDelegate,
                                              UITableViewDataSource,
                                              UISearchBarDelegate,
                                              UISearchDisplayDelegate>

@property (nonatomic, strong) IBOutlet UITableView *tableView;
@property (nonatomic, strong) IBOutlet UISearchBar *searchBar;

@end
