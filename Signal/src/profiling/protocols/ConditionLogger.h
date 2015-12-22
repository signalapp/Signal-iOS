#import <Foundation/Foundation.h>

@protocol ConditionLogger <NSObject>
- (void)logNotice:(id)details;
- (void)logWarning:(id)details;
- (void)logError:(id)details;
@end
