#import "AnonymousOccurrenceLogger.h"
#import "Constraints.h"

@implementation AnonymousOccurrenceLogger

+ (AnonymousOccurrenceLogger *)anonymousOccurencyLoggerWithMarker:(void (^)(id details))marker {
    ows_require(marker != nil);
    AnonymousOccurrenceLogger *a = [AnonymousOccurrenceLogger new];
    a->_marker                   = marker;
    return a;
}

- (void)markOccurrence:(id)details {
    _marker(details);
}

@end
