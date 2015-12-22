#import "NextResponderScrollView.h"

@implementation NextResponderScrollView

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    if (!self.dragging) {
        [self.nextResponder touchesBegan:touches withEvent:event];
    } else {
         [self.nextResponder touchesBegan:touches withEvent:event];

        [super touchesBegan:touches withEvent:event];
    }
}
- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    if (!self.dragging) {
        [self.nextResponder touchesEnded:touches withEvent:event];
    } else {
         [self.nextResponder touchesEnded:touches withEvent:event];
        [super touchesEnded:touches withEvent:event];
    }
}
- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    if (!self.dragging) {
        [self.nextResponder touchesCancelled:touches withEvent:event];
    } else {
        [self.nextResponder touchesCancelled:touches withEvent:event];

        [super touchesEnded:touches withEvent:event];
    }
}
@end
