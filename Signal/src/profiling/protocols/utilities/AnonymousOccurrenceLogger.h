#import <Foundation/Foundation.h>
#import "OccurrenceLogger.h"

@interface AnonymousOccurrenceLogger : NSObject <OccurrenceLogger>

@property (readonly, nonatomic, copy) void (^marker)(id details);

+ (AnonymousOccurrenceLogger *)anonymousOccurencyLoggerWithMarker:(void (^)(id details))marker;

@end
