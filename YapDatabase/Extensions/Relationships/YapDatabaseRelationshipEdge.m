#import "YapDatabaseRelationshipEdge.h"
#import "YapDatabaseRelationshipEdgePrivate.h"


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

/**
 * Public init method.
 * This method is used by objects when creating nodes (often in yapDatabaseRelationshipEdges method).
**/
- (id)initWithName:(NSString *)inName
    destinationKey:(NSString *)dstKey
        collection:(NSString *)dstCollection
   nodeDeleteRules:(YDB_NodeDeleteRules)rules
{
	if (inName == nil) return nil; // Edge requires name
	if (dstKey == nil) return nil; // Edge requires destination node
	
	if ((self = [super init]))
	{
		name = [inName copy];
		
		destinationKey = [dstKey copy];
		destinationCollection = dstCollection ? [dstCollection copy] : @"";
		
		nodeDeleteRules = rules;
	}
	return self;
}

/**
 * Internal init method.
 * This method is used when reading an edge from a row in the database.
**/
- (id)initWithRowid:(int64_t)rowid name:(NSString *)inName src:(int64_t)src dst:(int64_t)dst rules:(int)rules
{
	if ((self = [super init]))
	{
		edgeRowid = rowid;
		sourceRowid = src;
		destinationRowid = dst;
		
		name = [inName copy];
		
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
	
	copy->edgeRowid = edgeRowid;
	copy->sourceRowid = sourceRowid;
	copy->destinationRowid = destinationRowid;
	copy->edgeAction = edgeAction;
	copy->nodeAction = nodeAction;
	
	return copy;
}

- (id)copyWithSourceKey:(NSString *)newSrcKey collection:(NSString *)newSrcCollection rowid:(int64_t)newSrcRowid
{
	YapDatabaseRelationshipEdge *copy = [[YapDatabaseRelationshipEdge alloc] init];
	
	copy->name = name;
	copy->sourceKey = [newSrcKey copy];
	copy->sourceCollection = [newSrcCollection copy];
	copy->destinationKey = destinationKey;
	copy->destinationCollection = destinationCollection;
	copy->nodeDeleteRules = nodeDeleteRules;
	
	copy->edgeRowid = edgeRowid;
	copy->sourceRowid = newSrcRowid;
	copy->destinationRowid = destinationRowid;
	copy->edgeAction = edgeAction;
	copy->nodeAction = nodeAction;
	
	return copy;
}

@end
