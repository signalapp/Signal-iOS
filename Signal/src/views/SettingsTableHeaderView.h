#import <UIKit/UIKit.h>

/**
 *
 * The header view of the settings table view sections which handles rotating the image that indicates collapsed/expanded state
 *
 */

@interface SettingsTableHeaderView : UIView

@property (strong, nonatomic) IBOutlet UIImageView* columnStateImageView;

- (void)setColumnStateExpanded:(BOOL)isExpanded andIsAnimated:(BOOL)animated;

@end
