#import "CallTermination.h"
#import "LocalizableText.h"

@interface CallTermination ()

@property (readwrite, nonatomic) CallTerminationType type;
@property (strong, readwrite, nonatomic) id failure;
@property (strong, readwrite, nonatomic) id messageInfo;

@end

@implementation CallTermination

- (instancetype)initWithType:(CallTerminationType)type
                  andFailure:(id)failure
              andMessageInfo:(id)messageInfo {
    self = [super init];
	
    if (self) {
        self.type = type;
        self.failure = failure;
        self.messageInfo = messageInfo;
    }
    
    return self;
}

- (BOOL)isEqual:(id)object {
    return [object isKindOfClass:[CallTermination class]] && ((CallTermination*)object).type == self.type;
}

- (NSUInteger)hash {
    return self.type;
}

- (NSString*)description {
    return makeCallTerminationLocalizedTextDictionary()[self];
}

- (NSString*)localizedDescriptionForUser {
    return [self description];
}

- (id)copyWithZone:(NSZone*)zone {
    return [[CallTermination alloc] initWithType:self.type
                                      andFailure:[self.failure copyWithZone:zone]
                                  andMessageInfo:[self.messageInfo copyWithZone:zone]];
}

@end
