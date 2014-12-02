#import <UIKit/UIKit.h>


@interface EditViewController : UIViewController

@property (nonatomic, strong, readwrite) NSString *todoID;

@property (nonatomic, weak) IBOutlet UITextField *titleField;
@property (nonatomic, weak) IBOutlet UISegmentedControl *priority;

@property (nonatomic, weak) IBOutlet UILabel *uuidLabel;
@property (nonatomic, weak) IBOutlet UILabel *creationDateLabel;
@property (nonatomic, weak) IBOutlet UILabel *lastModifiedLabel;

@end
