#import "YapDatabaseRelationshipEdge.h"
#import "YapDatabaseRelationshipEdgePrivate.h"


@implementation YapDatabaseRelationshipEdge

@synthesize name = name;

@synthesize sourceCollection = sourceCollection;
@synthesize sourceKey = sourceKey;

@synthesize destinationCollection = destinationCollection;
@synthesize destinationKey = destinationKey;

@synthesize destinationFilePath = destinationFilePath;

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
         destinationFilePath:(NSString *)destinationFilePath
             nodeDeleteRules:(YDB_NodeDeleteRules)rules
{
	return [[YapDatabaseRelationshipEdge alloc] initWithName:name
	                                     destinationFilePath:destinationFilePath
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

+ (instancetype)edgeWithName:(NSString *)name
                   sourceKey:(NSString *)sourceKey
                  collection:(NSString *)sourceCollection
         destinationFilePath:(NSString *)destinationFilePath
             nodeDeleteRules:(YDB_NodeDeleteRules)rules
{
	return [[YapDatabaseRelationshipEdge alloc] initWithName:name
	                                               sourceKey:sourceKey
	                                              collection:sourceCollection
	                                     destinationFilePath:destinationFilePath
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
	if (dstKey == nil) return nil; // Edge requires destination
	
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
 * Suitable for use with YapDatabaseRelationshipNode protocol.
**/
- (id)initWithName:(NSString *)inName destinationFilePath:(NSString *)dstFilePath
                                          nodeDeleteRules:(YDB_NodeDeleteRules)rules
{
	if (inName == nil) return nil;      // Edge requires name
	if (dstFilePath == nil) return nil; // Edge requires destination
	
	if ((self = [super init]))
	{
		name = [inName copy];
		
		destinationFilePath = [dstFilePath copy];
		
		nodeDeleteRules = rules;
		isManualEdge = NO;
		
		flags = YDB_FlagsDestinationLookupSuccessful; // no need for destinationRowid lookup
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
	if (srcKey == nil) return nil; // Edge requires source
	if (dstKey == nil) return nil; // Edge requires destination
	
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

- (id)initWithName:(NSString *)inName sourceKey:(NSString *)srcKey
                                     collection:(NSString *)srcCollection
                            destinationFilePath:(NSString *)dstFilePath
                                nodeDeleteRules:(YDB_NodeDeleteRules)rules
{
	if (inName == nil) return nil;      // Edge requires name
	if (srcKey == nil) return nil;      // Edge requires source
	if (dstFilePath == nil) return nil; // Edge requires destination
	
	if ((self = [super init]))
	{
		name = [inName copy];
		
		sourceKey = [srcKey copy];
		sourceCollection = srcCollection ? [srcCollection copy] : @"";
		
		destinationFilePath = [dstFilePath copy];
		
		nodeDeleteRules = rules;
		isManualEdge = YES;
		
		flags = YDB_FlagsDestinationLookupSuccessful; // no need for destinationRowid lookup
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
		
		flags = YDB_FlagsSourceLookupSuccessful | YDB_FlagsDestinationLookupSuccessful;
	}
	return self;
}

- (id)initWithRowid:(int64_t)rowid
               name:(NSString *)inName
                src:(int64_t)src
        dstFilePath:(NSString *)dstFilePath
              rules:(int)rules
             manual:(BOOL)manual
{
	if ((self = [super init]))
	{
		edgeRowid = rowid;
		sourceRowid = src;
		destinationFilePath = [dstFilePath copy];
		
		name = [inName copy];
		
		nodeDeleteRules = rules;
		isManualEdge = manual;
		
		flags = YDB_FlagsSourceLookupSuccessful | YDB_FlagsDestinationLookupSuccessful;
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
		
		destinationFilePath = [decoder decodeObjectForKey:@"destinationFilePath"];
		
		nodeDeleteRules = [decoder decodeIntForKey:@"nodeDeleteRules"];
		isManualEdge = [decoder decodeBoolForKey:@"isManualEdge"];
		
		if (destinationFilePath)
			flags = YDB_FlagsDestinationLookupSuccessful;
		else
			flags = YDB_FlagsNone;
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
	
	[coder encodeObject:destinationFilePath forKey:@"destinationFilePath"];
	
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
	copy->destinationFilePath = destinationFilePath;
	copy->nodeDeleteRules = nodeDeleteRules;
	copy->isManualEdge = isManualEdge;
	
	copy->edgeRowid = edgeRowid;
	copy->sourceRowid = sourceRowid;
	copy->destinationRowid = destinationRowid;
	
	copy->edgeAction = YDB_EdgeActionNone; // Return a clean copy
	copy->flags = YDB_FlagsNone;           // Return a clean copy
	
	if (destinationFilePath)
		copy->flags |= YDB_FlagsDestinationLookupSuccessful;
	
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
	copy->destinationFilePath = destinationFilePath;
	copy->nodeDeleteRules = nodeDeleteRules;
	copy->isManualEdge = NO; // Force proper value
	
	copy->edgeRowid = edgeRowid;
	copy->sourceRowid = newSrcRowid;
	copy->destinationRowid = destinationRowid;
	
	copy->edgeAction = YDB_EdgeActionNone;         // Return a clean copy
	copy->flags = YDB_FlagsSourceLookupSuccessful; // Return a clean copy
	
	if (destinationFilePath)
		copy->flags = YDB_FlagsDestinationLookupSuccessful;
	
	return copy;
}

@end
