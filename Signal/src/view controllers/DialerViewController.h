#import <UIKit/UIKit.h>

#import "DialerButtonView.h"
#import "InteractiveLabel.h"
#import "PhoneNumber.h"

@interface DialerViewController : UIViewController <DialerButtonViewDelegate>

@property (nonatomic, strong) IBOutlet UIButton *backspaceButton;
@property (nonatomic, strong) IBOutlet InteractiveLabel *numberLabel;
@property (nonatomic, strong) IBOutlet UIButton *callButton;
@property (nonatomic, strong) IBOutlet UIButton *addContactButton;
@property (nonatomic, strong) IBOutlet UIImageView *matchedContactImageView;

@property (nonatomic, strong) IBOutlet DialerButtonView *button0;
@property (nonatomic, strong) IBOutlet DialerButtonView *button1;
@property (nonatomic, strong) IBOutlet DialerButtonView *button2;
@property (nonatomic, strong) IBOutlet DialerButtonView *button3;
@property (nonatomic, strong) IBOutlet DialerButtonView *button4;
@property (nonatomic, strong) IBOutlet DialerButtonView *button5;
@property (nonatomic, strong) IBOutlet DialerButtonView *button6;
@property (nonatomic, strong) IBOutlet DialerButtonView *button7;
@property (nonatomic, strong) IBOutlet DialerButtonView *button8;
@property (nonatomic, strong) IBOutlet DialerButtonView *button9;
@property (nonatomic, strong) IBOutlet DialerButtonView *buttonStar;
@property (nonatomic, strong) IBOutlet DialerButtonView *buttonPound;

@property (nonatomic, strong) PhoneNumber *phoneNumber;

- (IBAction)callButtonTapped;
- (IBAction)backspaceButtonTouchDown;
- (IBAction)backspaceButtonTouchUp;

- (void)popuateNumberLabelWithNumber:(PhoneNumber *)phoneNumber;

@end
