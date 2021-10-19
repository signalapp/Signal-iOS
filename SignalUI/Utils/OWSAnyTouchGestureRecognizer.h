//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// This custom GR can be used to detect touches when they
// begin in a view.  In order to honor touch dispatch, this
// GR will ignore touches that:
//
// * Are not single touches.
// * Are not in the view for this GR.
// * Are inside a visible, interaction-enabled subview.
@interface OWSAnyTouchGestureRecognizer : UIGestureRecognizer

@end

NS_ASSUME_NONNULL_END
