#import <UIKit/UIKit.h>


@interface ViewController : UIViewController <UITableViewDelegate, UITableViewDataSource>

/**
 * The AppDelegate invokes this method after it's prepared the database for us.
 *
 * The 'remainingKeys' parameter is a list of all keys (Person.uuid) that exist in the database,
 * but that are not contained within the manualView. In other words, when the user hits the 'plus'
 * button, we can randomly select a key from this array, and then add that person to the manualView.
**/
- (void)setRemainingKeys:(NSArray<NSString *> *)remainingKeys;

@end

