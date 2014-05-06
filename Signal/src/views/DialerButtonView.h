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
- (void)dialerButtonViewDidSelect:(DialerButtonView *)view;
@end

@interface DialerButtonView : UIView

@property (nonatomic, strong) NSString *buttonInput;
@property (nonatomic, strong) NSString *letterLocalizationKey;
@property (nonatomic, strong) NSString *numberLocalizationKey;

@property (nonatomic, strong) IBOutlet UILabel *numberLabel;
@property (nonatomic, strong) IBOutlet UILabel *letterLabel;
@property (nonatomic, assign) IBOutlet id<DialerButtonViewDelegate> delegate;

- (IBAction)buttonTouchUp;
- (IBAction)buttonTouchCancel;
- (IBAction)buttonTouchDown;

@end
