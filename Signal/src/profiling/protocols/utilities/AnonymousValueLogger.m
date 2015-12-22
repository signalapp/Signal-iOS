#import "AnonymousValueLogger.h"
#import "Constraints.h"

@implementation AnonymousValueLogger

+ (AnonymousValueLogger *)anonymousValueLogger:(void (^)(double value))logValue {
    ows_require(logValue != nil);
    AnonymousValueLogger *a = [AnonymousValueLogger new];
    a->_logValueBlock       = logValue;
    return a;
}

- (void)logValue:(double)value {
    _logValueBlock(value);
}

@end
