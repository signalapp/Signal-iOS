#import "MyTodo.h"

/**
 * Keys for encoding / decoding (to avoid typos)
**/
static NSString *const k_version      = @"version";
static NSString *const k_uuid         = @"uuid";
static NSString *const k_title        = @"title";
static NSString *const k_notes        = @"notes";
static NSString *const k_isDone       = @"isDone";
static NSString *const k_created      = @"created";
static NSString *const k_lastModified = @"lastModified";


@implementation MyTodo

@synthesize uuid = uuid;
@synthesize title = title;
@synthesize notes = notes;
@synthesize isDone = isDone;
@synthesize created = created;
@synthesize lastModified = lastModified;

- (instancetype)init
{
	return [self initWithUUID:[[NSUUID UUID] UUIDString]];
}

- (instancetype)initWithUUID:(NSString *)inUUID
{
	if ((self = [super init]))
	{
		uuid = [inUUID copy];
		created = [NSDate date];
	}
	return self;
}

#pragma mark NSCoding

- (instancetype)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super init]))
	{
		// The version can be used to handle on-the-fly upgrades to objects as they're decoded.
		// For more information, see the wiki article:
		// https://github.com/yapstudios/YapDatabase/wiki/Storing-Objects
	//	int version = [decoder decodeIntForKey:k_version];
		
		uuid = [decoder decodeObjectForKey:k_uuid];
		title = [decoder decodeObjectForKey:k_title];
		notes = [decoder decodeObjectForKey:k_notes];
		isDone = [decoder decodeBoolForKey:k_isDone];
		created = [decoder decodeObjectForKey:k_created];
		lastModified = [decoder decodeObjectForKey:k_lastModified];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeInt:1 forKey:k_version];
	
	[coder encodeObject:uuid forKey:k_uuid];
	[coder encodeObject:title forKey:k_title];
	[coder encodeObject:notes forKey:k_notes];
	[coder encodeBool:isDone forKey:k_isDone];
	[coder encodeObject:created forKey:k_created];
	[coder encodeObject:lastModified forKey:k_lastModified];
}

#pragma mark NSCopying

- (id)copyWithZone:(NSZone *)zone
{
	MyTodo *copy = [super copyWithZone:zone]; // Be sure to invoke [MyDatabaseObject copyWithZone:] !
	copy->uuid = uuid;
	copy->title = title;
	copy->notes = notes;
	copy->isDone = isDone;
	copy->created = created;
	copy->lastModified = lastModified;
	
	return copy;
}

#pragma mark KVO

- (void)setValue:(id)value forUndefinedKey:(NSString *)key
{
	// May be invoked if the corresponding CKRecord has:
	//
	// - Old/deprecated keys that are no longer available in this newer version.
	//   Likely the object was created/modified by an older version of the application.
	//   We should properly handle this case here.
	//
	// - New keys that aren't available in this older version.
	//   Likely the object was created/modified by a newer version of the application.
	//   We must silently ignore / handle the case here.
}

@end
