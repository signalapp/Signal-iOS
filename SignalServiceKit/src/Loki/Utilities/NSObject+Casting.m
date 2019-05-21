#import "NSObject+Casting.h"

@implementation NSObject (Casting)

- (instancetype)as:(Class)cls {
    if ([self isKindOfClass:cls]) { return self; }
    return nil;
}

@end
