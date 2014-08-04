//
//  NBPhoneNumberDesc.m
//  libPhoneNumber
//
//

#import "NBPhoneNumberDesc.h"
#import "NSArray+NBAdditions.h"

@implementation NBPhoneNumberDesc

@synthesize nationalNumberPattern, possibleNumberPattern, exampleNumber;


- (id)initWithData:(id)data
{
    self = [self init];
    
    if (self && data != nil && [data isKindOfClass:[NSArray class]])
    {
        /* 2 */ self.nationalNumberPattern = [data safeObjectAtIndex:2];
        /* 3 */ self.possibleNumberPattern = [data safeObjectAtIndex:3];
        /* 6 */ self.exampleNumber = [data safeObjectAtIndex:6];
    }
    
    return self;
}


- (id)init
{
    self = [super init];
    
    if (self)
    {
    }
    
    return self;
}


- (id)initWithCoder:(NSCoder*)coder
{
    if (self = [super init])
    {
        self.nationalNumberPattern = [coder decodeObjectForKey:@"nationalNumberPattern"];
        self.possibleNumberPattern = [coder decodeObjectForKey:@"possibleNumberPattern"];
        self.exampleNumber = [coder decodeObjectForKey:@"exampleNumber"];
    }
    return self;
}


- (void)encodeWithCoder:(NSCoder*)coder
{
    [coder encodeObject:self.nationalNumberPattern forKey:@"nationalNumberPattern"];
    [coder encodeObject:self.possibleNumberPattern forKey:@"possibleNumberPattern"];
    [coder encodeObject:self.exampleNumber forKey:@"exampleNumber"];
}


- (NSString *)description
{
    return [NSString stringWithFormat:@"nationalNumberPattern[%@] possibleNumberPattern[%@] exampleNumber[%@]", self.nationalNumberPattern, self.possibleNumberPattern, self.exampleNumber];
}

- (id)copyWithZone:(NSZone *)zone
{
	NBPhoneNumberDesc *phoneDescCopy = [[NBPhoneNumberDesc allocWithZone:zone] init];
    
    phoneDescCopy.nationalNumberPattern = [self.nationalNumberPattern copy];
    phoneDescCopy.possibleNumberPattern = [self.possibleNumberPattern copy];
    phoneDescCopy.exampleNumber = [self.exampleNumber copy];
    
	return phoneDescCopy;
}

- (BOOL)isEqual:(id)object
{
    if ([object isKindOfClass:[NBPhoneNumberDesc class]] == NO)
        return NO;
    
    NBPhoneNumberDesc *other = object;
    return [self.nationalNumberPattern isEqual:other.nationalNumberPattern] &&
        [self.possibleNumberPattern isEqual:other.possibleNumberPattern] &&
        [self.exampleNumber isEqual:other.exampleNumber];
}

@end
