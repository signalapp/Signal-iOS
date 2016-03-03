#import "TestObject.h"

@interface TestObjectMetadata ()
- (id)initWithSomeDate:(NSDate *)inDate someInt:(int)inInt;
@end

#pragma mark -

@implementation TestObject

+ (TestObject *)generateTestObject
{
	return [[TestObject alloc] init];
}

+ (TestObject *)generateTestObjectWithSomeDate:(NSDate *)someDate someInt:(int)someInt
{
	return [[TestObject alloc] initWithSomeDate:someDate someInt:someInt];
}

@synthesize someString;
@synthesize someNumber;
@synthesize someDate;
@synthesize someArray;
@synthesize someInt;
@synthesize someDouble;

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

- (uint32_t)randomInt
{
	return (int)arc4random_uniform(100);
}

- (double)randomDouble
{
	return (double)arc4random_uniform(100);
}

- (id)init
{
	return [self initWithSomeDate:nil someInt:[self randomInt]];
}

- (id)initWithSomeDate:(NSDate *)inSomeDate someInt:(int)inSomeInt
{
	if ((self = [super init]))
	{
		if (inSomeDate)
			someDate = inSomeDate;
		else
			someDate = [NSDate date];
		
		someString = [self randomString:32];
		someNumber = [NSNumber numberWithInt:[self randomInt]];
		
		someArray  = @[ [self randomString:8], [self randomString:8], [self randomString:8] ];
		
		someInt    = inSomeInt;
		someDouble = [self randomDouble];
	}
	return self;
}

- (id)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super init]))
	{
		someString = [decoder decodeObjectForKey:@"someString"];
		someNumber = [decoder decodeObjectForKey:@"someNumber"];
		someDate   = [decoder decodeObjectForKey:@"someDate"];
		someArray  = [decoder decodeObjectForKey:@"someArray"];
		someInt    = [decoder decodeDoubleForKey:@"someInt"];
		someDouble = [decoder decodeDoubleForKey:@"someDouble"];
	}
	return self;
}

//- (void)dealloc
//{
//	NSLog(@"Uncomment to add breakpoint here");
//}

- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeObject:someString forKey:@"someString"];
	[coder encodeObject:someNumber forKey:@"someNumber"];
	[coder encodeObject:someDate   forKey:@"someDate"];
	[coder encodeObject:someArray  forKey:@"someArray"];
	[coder encodeDouble:someInt    forKey:@"someInt"];
	[coder encodeDouble:someDouble forKey:@"someDouble"];
}

- (TestObjectMetadata *)extractMetadata
{
	return [[TestObjectMetadata alloc] initWithSomeDate:someDate someInt:someInt];
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation TestObjectMetadata

@synthesize someDate;
@synthesize someInt;

- (id)initWithSomeDate:(NSDate *)inDate someInt:(int)inInt
{
	if ((self = [super init]))
	{
		someDate = inDate;
		someInt = inInt;
	}
	return self;
}

- (id)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super init]))
	{
		someDate = [decoder decodeObjectForKey:@"someDate"];
		someInt = [decoder decodeIntForKey:@"someInt"];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeObject:someDate forKey:@"someDate"];
	[coder encodeInt:someInt forKey:@"someInt"];
}

@end
