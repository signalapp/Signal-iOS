//
//  NBPhoneNumberFormat.m
//  libPhoneNumber
//
//

#import "NBNumberFormat.h"
#import "NSArray+NBAdditions.h"

@implementation NBNumberFormat

@synthesize pattern, format, leadingDigitsPatterns, nationalPrefixFormattingRule, nationalPrefixOptionalWhenFormatting, domesticCarrierCodeFormattingRule;


- (id)initWithData:(id)data
{
    self = [self init];
    
    if (self && data != nil && [data isKindOfClass:[NSArray class]])
    {
        /* 1 */ self.pattern = [data safeObjectAtIndex:1];
        /* 2 */ self.format = [data safeObjectAtIndex:2];
        /* 3 */ self.leadingDigitsPatterns = [self stringArrayFromData:[data safeObjectAtIndex:3]]; // NSString array
        /* 4 */ self.nationalPrefixFormattingRule = [data safeObjectAtIndex:4];
        /* 6 */ self.nationalPrefixOptionalWhenFormatting = [[data safeObjectAtIndex:6] boolValue];
        /* 5 */ self.domesticCarrierCodeFormattingRule = [data safeObjectAtIndex:5];
    }
    
    return self;
}


- (id)init
{
    self = [super init];
    
    if (self)
    {
        self.nationalPrefixOptionalWhenFormatting = NO;
        self.leadingDigitsPatterns = [[NSMutableArray alloc] init];
    }
    
    return self;
}


- (NSMutableArray*)stringArrayFromData:(id)data
{
    NSMutableArray *resArray = [[NSMutableArray alloc] init];
    if (data != nil && [data isKindOfClass:[NSArray class]])
    {
        for (id numFormat in data)
        {
            if ([numFormat isKindOfClass:[NSString class]])
            {
                [resArray addObject:numFormat];
            }
            else
            {
                [resArray addObject:[numFormat stringValue]];
            }
        }
    }
    
    return resArray;
}


- (NSString *)description
{
    return [NSString stringWithFormat:@"[pattern:%@, format:%@, leadingDigitsPattern:%@, nationalPrefixFormattingRule:%@, nationalPrefixOptionalWhenFormatting:%@, domesticCarrierCodeFormattingRule:%@]",
            self.pattern, self.format, self.leadingDigitsPatterns, self.nationalPrefixFormattingRule, self.nationalPrefixOptionalWhenFormatting?@"Y":@"N", self.domesticCarrierCodeFormattingRule];
}


- (id)copyWithZone:(NSZone *)zone
{
	NBNumberFormat *phoneFormatCopy = [[NBNumberFormat allocWithZone:zone] init];
    
    /*
     1 @property (nonatomic, strong, readwrite) NSString *pattern;
     2 @property (nonatomic, strong, readwrite) NSString *format;
     3 @property (nonatomic, strong, readwrite) NSString *leadingDigitsPattern;
     4 @property (nonatomic, strong, readwrite) NSString *nationalPrefixFormattingRule;
     6 @property (nonatomic, assign, readwrite) BOOL nationalPrefixOptionalWhenFormatting;
     5 @property (nonatomic, strong, readwrite) NSString *domesticCarrierCodeFormattingRule;
    */
    
    phoneFormatCopy.pattern = [self.pattern copy];
    phoneFormatCopy.format = [self.format copy];
    phoneFormatCopy.leadingDigitsPatterns = [self.leadingDigitsPatterns copy];
    phoneFormatCopy.nationalPrefixFormattingRule = [self.nationalPrefixFormattingRule copy];
    phoneFormatCopy.nationalPrefixOptionalWhenFormatting = self.nationalPrefixOptionalWhenFormatting;
    phoneFormatCopy.domesticCarrierCodeFormattingRule = [self.domesticCarrierCodeFormattingRule copy];
    
	return phoneFormatCopy;
}


- (id)initWithCoder:(NSCoder*)coder
{
    if (self = [super init])
    {
        self.pattern = [coder decodeObjectForKey:@"pattern"];
        self.format = [coder decodeObjectForKey:@"format"];
        self.leadingDigitsPatterns = [coder decodeObjectForKey:@"leadingDigitsPatterns"];
        self.nationalPrefixFormattingRule = [coder decodeObjectForKey:@"nationalPrefixFormattingRule"];
        self.nationalPrefixOptionalWhenFormatting = [[coder decodeObjectForKey:@"nationalPrefixOptionalWhenFormatting"] boolValue];
        self.domesticCarrierCodeFormattingRule = [coder decodeObjectForKey:@"domesticCarrierCodeFormattingRule"];
    }
    return self;
}


- (void)encodeWithCoder:(NSCoder*)coder
{
    [coder encodeObject:self.pattern forKey:@"pattern"];
    [coder encodeObject:self.format forKey:@"format"];
    [coder encodeObject:self.leadingDigitsPatterns forKey:@"leadingDigitsPatterns"];
    [coder encodeObject:self.nationalPrefixFormattingRule forKey:@"nationalPrefixFormattingRule"];
    [coder encodeObject:[NSNumber numberWithBool:self.nationalPrefixOptionalWhenFormatting] forKey:@"nationalPrefixOptionalWhenFormatting"];
    [coder encodeObject:self.domesticCarrierCodeFormattingRule forKey:@"domesticCarrierCodeFormattingRule"];
}


- (void)setData:(id)data
{
    if ([data isKindOfClass:[NSArray class]] || [data isKindOfClass:[NSMutableArray class]])
    {
        
    }
    else if ([data isKindOfClass:[NSDictionary class]] || [data isKindOfClass:[NSMutableDictionary class]])
    {
        
    }
}

@end
