#import "CallTermination.h"
#import "LocalizableText.h"

@implementation CallTermination

@synthesize type, failure, messageInfo;

+ (CallTermination *)callTerminationOfType:(enum CallTerminationType)type
                               withFailure:(id)failure
                            andMessageInfo:(id)messageInfo {
    CallTermination *instance = [CallTermination new];
    instance->type            = type;
    instance->failure         = failure;
    instance->messageInfo     = messageInfo;
    return instance;
}

- (BOOL)isEqual:(id)object {
    return [object isKindOfClass:CallTermination.class] && ((CallTermination *)object).type == type;
}
- (NSUInteger)hash {
    return type;
}
- (NSString *)description {
    return makeCallTerminationLocalizedTextDictionary()[self];
}
- (NSString *)localizedDescriptionForUser {
    return [self description];
}

- (id)copyWithZone:(NSZone *)zone {
    return [CallTermination callTerminationOfType:type
                                      withFailure:[failure copyWithZone:zone]
                                   andMessageInfo:[messageInfo copyWithZone:zone]];
}

@end
