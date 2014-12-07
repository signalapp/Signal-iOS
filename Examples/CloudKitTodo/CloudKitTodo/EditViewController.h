#import <UIKit/UIKit.h>
#import "TodoTextView.h"


@interface EditViewController : UIViewController <UITextViewDelegate>

@property (nonatomic, strong, readwrite) NSString *todoID;

@property (nonatomic, weak) IBOutlet TodoTextView *titleView;

@property (nonatomic, weak) IBOutlet NSLayoutConstraint *titleViewHeightConstraint;
@property (nonatomic, weak) IBOutlet NSLayoutConstraint *titleViewMinHeightConstraint;
@property (nonatomic, weak) IBOutlet NSLayoutConstraint *titleViewMaxHeightConstraint;

@property (nonatomic, weak) IBOutlet UIButton *checkmarkButton;
@property (nonatomic, weak) IBOutlet UISegmentedControl *priority;

@property (nonatomic, weak) IBOutlet UILabel *uuidLabel;
@property (nonatomic, weak) IBOutlet UILabel *creationDateLabel;
@property (nonatomic, weak) IBOutlet UILabel *lastModifiedLabel;

@property (nonatomic, weak) IBOutlet UILabel *baseRecordLabel;

@end
