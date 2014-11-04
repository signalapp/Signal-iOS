#import "AnonymousValueLogger.h"
#import "Constraints.h"

@interface AnonymousValueLogger ()

@property (nonatomic, readwrite, copy) void (^logValueBlock)(double value);

@end

@implementation AnonymousValueLogger

- (instancetype)initWithLogValue:(void(^)(double value))logValue {
    if (self = [super init]) {
        require(logValue != nil);
        self.logValueBlock = logValue;
    }
    
    return self;
}

#pragma mark ValueLogger

- (void)logValue:(double)value {
    self.logValueBlock(value);
}

@end
