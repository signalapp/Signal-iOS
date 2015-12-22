#import <Foundation/Foundation.h>

/// Cancels something when terminate is called.
/// It must be safe to call terminate multiple times.
@protocol Terminable <NSObject>
- (void)terminate;
@end
