#import "RecipientUnavailable.h"

@implementation RecipientUnavailable

+(RecipientUnavailable*) recipientUnavailable {
    return [RecipientUnavailable new];
}

-(NSString *)description {
    return @"Recipient unavailable";
}

@end
