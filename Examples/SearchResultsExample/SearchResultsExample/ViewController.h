#import <UIKit/UIKit.h>


@interface ViewController : UIViewController <UITableViewDelegate,
                                              UITableViewDataSource,
                                              UISearchBarDelegate,
                                              UISearchDisplayDelegate>

@property (nonatomic, strong) IBOutlet UITableView *mainTableView;

@end
