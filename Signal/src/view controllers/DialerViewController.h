#import <UIKit/UIKit.h>

#import "DialerButtonView.h"
#import "InteractiveLabel.h"
#import "PhoneNumber.h"

@interface DialerViewController : UIViewController <DialerButtonViewDelegate>

@property (strong, nonatomic) IBOutlet UIButton* backspaceButton;
@property (strong, nonatomic) IBOutlet InteractiveLabel* numberLabel;
@property (strong, nonatomic) IBOutlet UIButton* callButton;
@property (strong, nonatomic) IBOutlet UIButton* addContactButton;
@property (strong, nonatomic) IBOutlet UIImageView* matchedContactImageView;

@property (strong, nonatomic) IBOutlet DialerButtonView* button0;
@property (strong, nonatomic) IBOutlet DialerButtonView* button1;
@property (strong, nonatomic) IBOutlet DialerButtonView* button2;
@property (strong, nonatomic) IBOutlet DialerButtonView* button3;
@property (strong, nonatomic) IBOutlet DialerButtonView* button4;
@property (strong, nonatomic) IBOutlet DialerButtonView* button5;
@property (strong, nonatomic) IBOutlet DialerButtonView* button6;
@property (strong, nonatomic) IBOutlet DialerButtonView* button7;
@property (strong, nonatomic) IBOutlet DialerButtonView* button8;
@property (strong, nonatomic) IBOutlet DialerButtonView* button9;
@property (strong, nonatomic) IBOutlet DialerButtonView* buttonStar;
@property (strong, nonatomic) IBOutlet DialerButtonView* buttonPound;

@property (strong, nonatomic) PhoneNumber* phoneNumber;

- (IBAction)callButtonTapped;
- (IBAction)backspaceButtonTouchDown;
- (IBAction)backspaceButtonTouchUp;

@end
