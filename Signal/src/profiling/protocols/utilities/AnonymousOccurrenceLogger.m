#import "AnonymousOccurrenceLogger.h"
#import "Constraints.h"

@interface AnonymousOccurrenceLogger ()

@property (nonatomic, readwrite, copy) void (^marker)(id details);

@end

@implementation AnonymousOccurrenceLogger

- (instancetype)initWithMarker:(void(^)(id details))marker {
    if (self = [super init]) {
        require(marker != nil);
        self.marker = marker;
    }
    
    return self;
}

#pragma mark OccurrenceLogger

- (void)markOccurrence:(id)details {
    self.marker(details);
}

@end
