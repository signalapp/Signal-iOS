#import "YapDatabaseRelationshipEdge.h"
#import "YapDatabaseRelationshipEdgePrivate.h"


@implementation YapDatabaseRelationshipEdge

@synthesize name = name;

@synthesize sourceCollection = sourceCollection;
@synthesize sourceKey = sourceKey;

@synthesize destinationCollection = destinationCollection;
@synthesize destinationKey = destinationKey;

@synthesize nodeDeleteRules = nodeDeleteRules;
@synthesize isManualEdge = isManualEdge;


+ (instancetype)edgeWithName:(NSString *)name
              destinationKey:(NSString *)destinationKey
                  collection:(NSString *)destinationCollection
             nodeDeleteRules:(YDB_NodeDeleteRules)rules
{
	return [[YapDatabaseRelationshipEdge alloc] initWithName:name
	                                          destinationKey:destinationKey
	                                              collection:destinationCollection
	                                         nodeDeleteRules:rules];
}

+ (instancetype)edgeWithName:(NSString *)name
                   sourceKey:(NSString *)sourceKey
                  collection:(NSString *)sourceCollection
              destinationKey:(NSString *)destinationKey
                  collection:(NSString *)destinationCollection
             nodeDeleteRules:(YDB_NodeDeleteRules)rules
{
	return [[YapDatabaseRelationshipEdge alloc] initWithName:name
	                                               sourceKey:sourceKey
	                                              collection:sourceCollection
	                                          destinationKey:destinationKey
	                                              collection:destinationCollection
	                                         nodeDeleteRules:rules];
}

/**
 * Public init method.
 * Suitable for use with YapDatabaseRelationshipNode protocol.
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
		isManualEdge = NO;
	}
	return self;
}

/**
 * Public init method.
 * Suitable for use with manual edge management.
**/
- (id)initWithName:(NSString *)inName
         sourceKey:(NSString *)srcKey
        collection:(NSString *)srcCollection
    destinationKey:(NSString *)dstKey
        collection:(NSString *)dstCollection
   nodeDeleteRules:(YDB_NodeDeleteRules)rules
{
	if (inName == nil) return nil; // Edge requires name
	if (srcKey == nil) return nil; // Edge requires sourceKey
	if (dstKey == nil) return nil; // Edge requires destinationKey
	
	if ((self = [super init]))
	{
		name = [inName copy];
		
		sourceKey = [srcKey copy];
		sourceCollection = srcCollection ? [srcCollection copy] : @"";
		
		destinationKey = [dstKey copy];
		destinationCollection = dstCollection ? [dstCollection copy] : @"";
		
		nodeDeleteRules = rules;
		isManualEdge = YES;
	}
	return self;
}

/**
 * Internal init method.
 * This method is used when reading an edge from a row in the database.
**/
- (id)initWithRowid:(int64_t)rowid
               name:(NSString *)inName
                src:(int64_t)src
                dst:(int64_t)dst
              rules:(int)rules
             manual:(BOOL)manual
{
	if ((self = [super init]))
	{
		edgeRowid = rowid;
		sourceRowid = src;
		destinationRowid = dst;
		
		name = [inName copy];
		
		nodeDeleteRules = rules;
		isManualEdge = manual;
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
		isManualEdge = [decoder decodeBoolForKey:@"isManualEdge"];
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
	[coder encodeBool:isManualEdge forKey:@"isManualEdge"];
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
	copy->isManualEdge = isManualEdge;
	
	copy->edgeRowid = edgeRowid;
	copy->sourceRowid = sourceRowid;
	copy->destinationRowid = destinationRowid;
	
	copy->edgeAction = YDB_EdgeActionNone; // Return a clean copy
	copy->flags = YDB_FlagsNone;           // Return a clean copy
	
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
	copy->isManualEdge = NO; // Force proper value
	
	copy->edgeRowid = edgeRowid;
	copy->sourceRowid = newSrcRowid;
	copy->destinationRowid = destinationRowid;
	
	copy->edgeAction = YDB_EdgeActionNone; // Return a clean copy
	copy->flags = YDB_FlagsNone;           // Return a clean copy
	
	return copy;
}

@end
