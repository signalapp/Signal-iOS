#import <Foundation/Foundation.h>

@protocol OccurrenceLogger <NSObject>
- (void)markOccurrence:(id)details;
@end
