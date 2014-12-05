#import "MyTodo.h"

/**
 * Keys for encoding / decoding (to avoid typos)
**/
static NSString *const k_version      = @"version";
static NSString *const k_uuid         = @"uuid";
static NSString *const k_title        = @"title";
static NSString *const k_priority     = @"priority";
static NSString *const k_isDone       = @"isDone";
static NSString *const k_creationDate = @"created";
static NSString *const k_lastModified = @"lastModified";


@implementation MyTodo

@synthesize uuid = uuid;
@synthesize title = title;
@synthesize priority = priority;
@synthesize isDone = isDone;
@synthesize creationDate = creationDate;
@synthesize lastModified = lastModified;

- (instancetype)init
{
	return [self initWithUUID:[[NSUUID UUID] UUIDString]];
}

- (instancetype)initWithUUID:(NSString *)inUUID
{
	if ((self = [super init]))
	{
		if (inUUID)
			uuid = [inUUID copy];
		else
			uuid = [[NSUUID UUID] UUIDString];
		
		priority = TodoPriorityNormal;
		creationDate = lastModified = [NSDate date];
	}
	return self;
}

- (instancetype)initWithRecord:(CKRecord *)record
{
	if (![record.recordType isEqualToString:@"todo"])
	{
		NSAssert(NO, @"Attempting to create todo from non-todo record"); // For debug builds
		return nil;                                                      // For release builds
	}
	
	if ((self = [super init]))
	{
		uuid = record.recordID.recordName;
		
		title = [record objectForKey:@"title"];
		priority = [[record objectForKey:@"priority"] integerValue];
		isDone = [[record objectForKey:@"isDone"] boolValue];
		
		creationDate = [record objectForKey:@"created"];
		lastModified = [record objectForKey:@"lastModified"];
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
		priority = [decoder decodeIntegerForKey:k_priority];
		isDone = [decoder decodeBoolForKey:k_isDone];
		creationDate = [decoder decodeObjectForKey:k_creationDate];
		lastModified = [decoder decodeObjectForKey:k_lastModified];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeInt:1 forKey:k_version];
	
	[coder encodeObject:uuid forKey:k_uuid];
	[coder encodeObject:title forKey:k_title];
	[coder encodeInteger:priority forKey:k_priority];
	[coder encodeBool:isDone forKey:k_isDone];
	[coder encodeObject:creationDate forKey:k_creationDate];
	[coder encodeObject:lastModified forKey:k_lastModified];
}

#pragma mark NSCopying

- (id)copyWithZone:(NSZone *)zone
{
	MyTodo *copy = [super copyWithZone:zone]; // Be sure to invoke [MyDatabaseObject copyWithZone:] !
	copy->uuid = uuid;
	copy->title = title;
	copy->priority = priority;
	copy->isDone = isDone;
	copy->creationDate = creationDate;
	copy->lastModified = lastModified;
	
	return copy;
}

#pragma mark MyDatabaseObject overrides

+ (NSMutableDictionary *)syncablePropertyMappings
{
	NSMutableDictionary *syncablePropertyMappings = [super syncablePropertyMappings];
	[syncablePropertyMappings setObject:@"created" forKey:@"creationDate"];
	
	return syncablePropertyMappings;
}

#pragma mark KVO

- (void)setValue:(id)value forUndefinedKey:(NSString *)key
{
	if ([key isEqualToString:@"created"]) {
		[self setValue:value forKey:@"creationDate"];
	}
	else
	{
		// May also be invoked if the corresponding CKRecord has:
		//
		// - Old/deprecated keys that are no longer available in this newer version.
		//   Likely the object was created/modified by an older version of the application.
		//   We should properly handle this case here.
		//
		// - New keys that aren't available in this older version.
		//   Likely the object was created/modified by a newer version of the application.
		//   We must silently ignore / handle the case here.
	}
}

- (id)valueForUndefinedKey:(NSString *)key
{
	if ([key isEqualToString:@"created"])
		return creationDate;
	else
		return [super valueForUndefinedKey:key];
}

@end
