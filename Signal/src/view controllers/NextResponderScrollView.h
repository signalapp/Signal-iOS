#import <UIKit/UIKit.h>

/**
 *
 * This scroll view is used in inbox feed table cell to pass touches through to the next responder-
 * because the scroll view touches override the table cell touches otherwise.
 *
 */

@interface NextResponderScrollView : UIScrollView

@end
