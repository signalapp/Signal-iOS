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

#pragma mark Class Init

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

#pragma mark Init

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
		
		flags = YDB_FlagsHasDestinationRowid; // no need for destinationRowid lookup
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
		
		flags = YDB_FlagsHasDestinationRowid; // no need for destinationRowid lookup
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
        dstFilePath:(NSString *)dstFilePath
              rules:(int)rules
             manual:(BOOL)manual
{
	if ((self = [super init]))
	{
		name = [inName copy];
		destinationFilePath = [dstFilePath copy];
		nodeDeleteRules = rules;
		isManualEdge = manual;
		
		edgeRowid = rowid;
		sourceRowid = src;
		destinationRowid = dst;
		
		flags = YDB_FlagsHasSourceRowid | YDB_FlagsHasDestinationRowid | YDB_FlagsHasEdgeRowid;
	}
	return self;
}

#pragma mark NSCoding

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
			flags = YDB_FlagsHasDestinationRowid;
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

#pragma mark NSCopying

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
	
	// Set appropriate flags
	
	if ((flags & YDB_FlagsHasSourceRowid))
		copy->flags |= YDB_FlagsHasSourceRowid;
	
	if ((flags & YDB_FlagsHasDestinationRowid) || destinationFilePath)
		copy->flags |= YDB_FlagsHasDestinationRowid;
	
	if ((flags & YDB_FlagsHasEdgeRowid))
		copy->flags |= YDB_FlagsHasEdgeRowid;
	
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
	
	copy->edgeAction = YDB_EdgeActionNone; // Return a clean copy
	copy->flags = YDB_FlagsNone;           // Return a clean copy
	
	// Set appropriate flags
	
	copy->flags |= YDB_FlagsHasSourceRowid;
	
	if ((flags & YDB_FlagsHasDestinationRowid) || destinationFilePath)
		copy->flags |= YDB_FlagsHasDestinationRowid;
	
	if ((flags & YDB_FlagsHasEdgeRowid))
		copy->flags |= YDB_FlagsHasEdgeRowid;
	
	return copy;
}

#pragma mark Comparison

/**
 * Compares two manual edges to see if they represent the same relationship.
 * That is, if both edges are manual edges, and the following are equal:
 *
 * - name
 * - sourceKey / sourceCollection
 * - destinationKey / destinationCollection
 * - destinationFilePath
 *
 * The nodeDeleteRules do NOT need to match.
**/
- (BOOL)matchesManualEdge:(YapDatabaseRelationshipEdge *)edge
{
	if (edge == nil) return NO;
	
	if (!isManualEdge) return NO;
	if (!edge->isManualEdge) return NO;
	
	if (![name isEqualToString:edge->name]) return NO;
	
	if (![sourceKey isEqualToString:edge->sourceKey]) return NO;
	if (![sourceCollection isEqualToString:edge->sourceCollection]) return NO;
	
	if (destinationFilePath)
	{
		if (![destinationFilePath isEqualToString:edge->destinationFilePath]) return NO;
	}
	else
	{
		if (![destinationKey isEqualToString:edge->destinationKey]) return NO;
		if (![destinationCollection isEqualToString:edge->destinationCollection]) return NO;
	}
	
	return YES;
}

#pragma mark Description

- (NSString *)description
{
	// Create rules string
	
	NSMutableString *rulesStr = [NSMutableString stringWithCapacity:64];

	if (nodeDeleteRules & YDB_NotifyIfSourceDeleted)
		[rulesStr appendString:@"NotifyIfSourceDeleted, "];
	
	if (nodeDeleteRules & YDB_NotifyIfDestinationDeleted)
		[rulesStr appendString:@"NotifyIfDestinationDeleted, "];
	
	if (nodeDeleteRules & YDB_DeleteSourceIfDestinationDeleted)
		[rulesStr appendString:@"DeleteSourceIfDestinationDeleted, "];
	
	if (nodeDeleteRules & YDB_DeleteDestinationIfSourceDeleted)
		[rulesStr appendString:@"DeleteDestinationIfSourceDeleted, "];
	
	if (nodeDeleteRules & YDB_DeleteSourceIfAllDestinationsDeleted)
		[rulesStr appendString:@"DeleteSourceIfAllDestinationsDeleted, "];
	
	if (nodeDeleteRules & YDB_DeleteDestinationIfAllSourcesDeleted)
		[rulesStr appendString:@"DeleteDestinationIfAllSourcesDeleted, "];
	
	if ([rulesStr length] > 0)
		[rulesStr deleteCharactersInRange:NSMakeRange([rulesStr length] - 2, 2)];
	
	// Create flags description
	
	NSMutableString *flagsStr = [NSMutableString stringWithCapacity:64];
	
	if (flags & YDB_FlagsSourceDeleted)
		[flagsStr appendString:@"SourceDeleted, "];
	
	if (flags & YDB_FlagsDestinationDeleted)
		[flagsStr appendString:@"DestinationDeleted, "];
	
	if (flags & YDB_FlagsBadSource)
		[flagsStr appendString:@"BadSource, "];
	
	if (flags & YDB_FlagsBadDestination)
		[flagsStr appendString:@"BadDestination, "];
	
	if (flags & YDB_FlagsHasSourceRowid)
		[flagsStr appendString:@"HasSourceRowid, "];
	
	if (flags & YDB_FlagsHasDestinationRowid)
		[flagsStr appendString:@"HasDestinationRowid, "];
	
	if (flags & YDB_FlagsHasEdgeRowid)
		[flagsStr appendString:@"HasEdgeRowid, "];
	
	if (flags & YDB_FlagsNotInDatabase)
		[flagsStr appendString:@"NotInDatabase, "];
	
	if ([flagsStr length] > 0)
		[flagsStr deleteCharactersInRange:NSMakeRange([flagsStr length] - 2, 2)];
	
	// Create edge description
	
	NSMutableString *description = [NSMutableString stringWithCapacity:128];
	
	[description appendFormat:@"<YapDatabaseRelationshipEdge[%p]", self];
	[description appendFormat:@" name(%@)", name];
	
	if (sourceKey)
		[description appendFormat:@" src(%@, %@)", sourceKey, (sourceCollection ?: @"")];
	else if (flags & YDB_FlagsHasSourceRowid)
		[description appendFormat:@" srcRowid(%lld)", sourceRowid];
	
	if (destinationKey)
		[description appendFormat:@" dst(%@, %@)", destinationKey, (destinationCollection ?: @"")];
	else if (destinationFilePath)
		[description appendFormat:@" dstFilePath(%@)", destinationFilePath];
	else if (flags & YDB_FlagsHasDestinationRowid)
		[description appendFormat:@" dstRowid(%lld)", destinationRowid];
	
	[description appendFormat:@" rules(%@)", rulesStr];
	
	if ([flagsStr length] > 0) {
		[description appendFormat:@" flags(%@)", flagsStr];
	}
	
	if (isManualEdge) {
		[description appendString:@" manual"];
	}
	
	[description appendString:@">"];
	
	return description;
}

@end
