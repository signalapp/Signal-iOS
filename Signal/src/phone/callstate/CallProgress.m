#import "CallProgress.h"
#import "LocalizableText.h"

@implementation CallProgress

@synthesize type;

+ (CallProgress *)callProgressWithType:(enum CallProgressType)type {
    CallProgress *instance = [CallProgress new];
    instance->type         = type;
    return instance;
}

- (BOOL)isEqual:(id)object {
    return [object isKindOfClass:CallProgress.class] && ((CallProgress *)object).type == type;
}
- (NSUInteger)hash {
    return type;
}
- (NSString *)description {
    return makeCallProgressLocalizedTextDictionary()[self];
}
- (NSString *)localizedDescriptionForUser {
    return [self description];
}

- (id)copyWithZone:(NSZone *)zone {
    return [CallProgress callProgressWithType:type];
}

@end
