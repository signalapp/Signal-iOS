#import <UIKit/UIKit.h>

/**
 *
 * This class exists because a UIButton can't have 2 lines of text.
 * DialerButtonView gives us customization and also localizes the label text.
 * Localize text by the setting properties in the xib for letterLocalizationKey and numberLocalizationKey.
 * A protocol is implemented to pass touch events for touchUpInside.
 *
 */

@class DialerButtonView;

@protocol DialerButtonViewDelegate  <NSObject>

- (void)dialerButtonViewDidSelect:(DialerButtonView*)view;

@end

@interface DialerButtonView : UIView

@property (strong, nonatomic) NSString* buttonInput;
@property (strong, nonatomic) NSString* letterLocalizationKey;
@property (strong, nonatomic) NSString* numberLocalizationKey;

@property (strong, nonatomic) IBOutlet UILabel* numberLabel;
@property (strong, nonatomic) IBOutlet UILabel* letterLabel;
@property (weak, nonatomic) IBOutlet id<DialerButtonViewDelegate> delegate;

- (IBAction)buttonTouchUp;
- (IBAction)buttonTouchCancel;
- (IBAction)buttonTouchDown;

@end
