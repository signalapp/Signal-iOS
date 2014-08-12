#import "Person.h"

@implementation Person

@synthesize name = name;
@synthesize uuid = uuid;

- (id)initWithName:(NSString *)inName uuid:(NSString *)inUuid
{
	if ((self = [super init]))
	{
		name = [inName copy];
		uuid = [inUuid copy];
	}
	return self;
}

#pragma mark NSCoding

/**
 * Deserializes a Person object.
 * 
 * For more information about serialization/deserialization, see the wiki article:
 * https://github.com/yaptv/YapDatabase/wiki/Storing-Objects
**/
- (id)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super init]))
	{
		name = [decoder decodeObjectForKey:@"name"];
		uuid = [decoder decodeObjectForKey:@"uuid"];
	}
	return self;
}

/**
 * Serializes a Person object.
**/
- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeObject:name forKey:@"name"];
	[coder encodeObject:uuid forKey:@"uuid"];
}

@end
