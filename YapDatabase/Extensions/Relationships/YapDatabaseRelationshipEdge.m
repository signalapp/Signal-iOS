#import "YapDatabaseRelationshipEdge.h"


@implementation YapDatabaseRelationshipEdge

@synthesize name = name;

@synthesize sourceCollection = sourceCollection;
@synthesize sourceKey = sourceKey;

@synthesize destinationCollection = destinationCollection;
@synthesize destinationKey = destinationKey;

@synthesize nodeDeleteRules = nodeDeleteRules;

+ (instancetype)edgeWithName:(NSString *)name
              destinationKey:(NSString *)key
                  collection:(NSString *)collection
             nodeDeleteRules:(YDB_NodeDeleteRules)rules
{
	return [[YapDatabaseRelationshipEdge alloc] initWithName:name
	                                          destinationKey:key
	                                              collection:collection
	                                         nodeDeleteRules:rules];
}

- (id)initWithName:(NSString *)inName
    destinationKey:(NSString *)dstKey
        collection:(NSString *)dstCollection
   nodeDeleteRules:(YDB_NodeDeleteRules)rules
{
	if ((self = [super init]))
	{
		name = [inName copy];
		
		destinationKey = [dstKey copy];
		destinationCollection = [dstCollection copy];
		
		nodeDeleteRules = rules;
	}
	return self;
}

- (id)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super init]))
	{
		name = [decoder decodeObjectForKey:@"name"];
		
		sourceKey = [decoder decodeObjectForKey:@"sourceKey"];
		sourceCollection = [decoder decodeObjectForKey:@"sourceCollection"];
		
		destinationKey = [decoder decodeObjectForKey:@"destinationKey"];
		destinationCollection = [decoder decodeObjectForKey:@"destinationCollection"];
		
		nodeDeleteRules = [decoder decodeIntForKey:@"nodeDeleteRules"];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeObject:name forKey:@"name"];
	
	[coder encodeObject:sourceKey forKey:@"sourceKey"];
	[coder encodeObject:sourceCollection forKey:@"sourceCollection"];
	
	[coder encodeObject:destinationKey forKey:@"destinationKey"];
	[coder encodeObject:destinationCollection forKey:@"destinationCollection"];
	
	[coder encodeInt:nodeDeleteRules forKey:@"nodeDeleteRules"];
}

- (id)copyWithZone:(NSZone *)zone
{
	YapDatabaseRelationshipEdge *copy = [[YapDatabaseRelationshipEdge alloc] init];
	copy->name = name;
	copy->sourceKey = sourceKey;
	copy->sourceCollection = sourceCollection;
	copy->destinationKey = destinationKey;
	copy->destinationCollection = destinationCollection;
	copy->nodeDeleteRules = nodeDeleteRules;
	
	return copy;
}

- (id)copyWithSourceKey:(NSString *)newSourceKey collection:(NSString *)newSourceCollection
{
	YapDatabaseRelationshipEdge *copy = [[YapDatabaseRelationshipEdge alloc] init];
	copy->name = name;
	copy->sourceKey = [newSourceKey copy];
	copy->sourceCollection = [newSourceCollection copy];
	copy->destinationKey = destinationKey;
	copy->destinationCollection = destinationCollection;
	copy->nodeDeleteRules = nodeDeleteRules;
	
	return copy;
}

@end
