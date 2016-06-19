#import <UIKit/UIKit.h>


@interface ViewController : UIViewController <UITableViewDelegate,
                                              UITableViewDataSource,
                                              UISearchResultsUpdating>

@property (nonatomic, strong) IBOutlet UITableView *mainTableView;
@property (nonatomic, strong) IBOutlet UITableView *searchResultsTableView;

@end

