#import "CallProgress.h"
#import "LocalizableText.h"

@interface CallProgress ()

@property (nonatomic, readwrite) CallProgressType type;

@end

@implementation CallProgress

- (instancetype)initWithType:(CallProgressType)type {
    if (self = [super init]) {
        self.type = type;
    }
    
    return self;
}

- (BOOL)isEqual:(id)object {
    return [object isKindOfClass:[CallProgress class]] && ((CallProgress*)object).type == self.type;
}

- (NSUInteger)hash {
    return self.type;
}

- (NSString*)description {
    return makeCallProgressLocalizedTextDictionary()[self];
}

- (NSString*)localizedDescriptionForUser {
    return [self description];
}

- (id)copyWithZone:(NSZone*)zone {
    return [[CallProgress alloc] initWithType:self.type];
}

@end
