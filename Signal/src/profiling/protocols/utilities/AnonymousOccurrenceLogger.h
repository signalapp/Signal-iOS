#import <Foundation/Foundation.h>
#import "OccurrenceLogger.h"

@interface AnonymousOccurrenceLogger : NSObject <OccurrenceLogger>

@property (nonatomic, readonly, copy) void (^marker)(id details);

- (instancetype)initWithMarker:(void(^)(id details))marker;

@end
