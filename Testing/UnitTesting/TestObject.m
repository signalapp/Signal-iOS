#import "TestObject.h"

@interface TestObjectMetadata ()
- (id)initWithString1:(NSString *)inString1 pDouble:(double)inPDouble;
@end

#pragma mark -

@implementation TestObject

+ (TestObject *)generateTestObject {
	return [[TestObject alloc] init];
}

@synthesize string1;
@synthesize string2;
@synthesize string3;
@synthesize string4;
@synthesize number;
@synthesize array;
@synthesize pDouble;

- (NSString *)randomString:(NSUInteger)length
{
	NSString *alphabet = @"abcdefghijklmnopqrstuvwxyz";
	NSUInteger alphabetLength = [alphabet length];
	
	NSMutableString *result = [NSMutableString stringWithCapacity:length];
	
	NSUInteger i;
	for (i = 0; i < length; i++)
	{
		uint32_t randomIndex = arc4random_uniform((uint32_t)alphabetLength);
		unichar c = [alphabet characterAtIndex:(NSUInteger)randomIndex];
		
		[result appendFormat:@"%C", c];
	}
	
	return result;
}

- (double)randomDouble
{
	return (double)arc4random_uniform(100);
}

- (id)init
{
	if ((self = [super init]))
	{
		string1 = [self randomString:32];
		string2 = [self randomString:32];
		string3 = [self randomString:32];
		string4 = [self randomString:32];
		
		number  = [NSNumber numberWithDouble:[self randomDouble]];
		
		array   = @[ [self randomString:8], [self randomString:8], [self randomString:8] ];
		
		pDouble = [self randomDouble];
	}
	return self;
}

- (id)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super init]))
	{
		string1 = [decoder decodeObjectForKey:@"string1"];
		string2 = [decoder decodeObjectForKey:@"string2"];
		string3 = [decoder decodeObjectForKey:@"string3"];
		string4 = [decoder decodeObjectForKey:@"string4"];
		number  = [decoder decodeObjectForKey:@"number"];
		array   = [decoder decodeObjectForKey:@"array"];
		pDouble = [decoder decodeDoubleForKey:@"pDouble"];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeObject:string1 forKey:@"string1"];
	[coder encodeObject:string2 forKey:@"string2"];
	[coder encodeObject:string3 forKey:@"string3"];
	[coder encodeObject:string4 forKey:@"string4"];
	[coder encodeObject:number  forKey:@"number"];
	[coder encodeObject:array   forKey:@"array"];
	[coder encodeDouble:pDouble forKey:@"pDouble"];
}

- (TestObjectMetadata *)extractMetadata
{
	return [[TestObjectMetadata alloc] initWithString1:string1 pDouble:pDouble];
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation TestObjectMetadata

@synthesize string1;
@synthesize pDouble;

- (id)initWithString1:(NSString *)inString1 pDouble:(double)inPDouble
{
	if ((self = [super init]))
	{
		string1 = inString1;
		pDouble = inPDouble;
	}
	return self;
}

- (id)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super init]))
	{
		string1 = [decoder decodeObjectForKey:@"string1"];
		pDouble = [decoder decodeDoubleForKey:@"pDouble"];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeObject:string1 forKey:@"string1"];
	[coder encodeDouble:pDouble forKey:@"pDouble"];
}

@end
