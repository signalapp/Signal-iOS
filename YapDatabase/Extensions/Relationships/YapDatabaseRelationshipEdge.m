#import "YapDatabaseRelationshipEdge.h"
#import "YapDatabaseRelationshipEdgePrivate.h"


@implementation YapDatabaseRelationshipEdge

@synthesize name = name;

@synthesize sourceCollection = sourceCollection;
@synthesize sourceKey = sourceKey;

@synthesize destinationCollection = destinationCollection;
@synthesize destinationKey = destinationKey;

@synthesize destinationFileURL = destinationFileURL;

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
          destinationFileURL:(NSURL *)destinationFileURL
             nodeDeleteRules:(YDB_NodeDeleteRules)rules
{
	return [[YapDatabaseRelationshipEdge alloc] initWithName:name
	                                      destinationFileURL:destinationFileURL
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
          destinationFileURL:(NSURL *)destinationFileURL
             nodeDeleteRules:(YDB_NodeDeleteRules)rules
{
	return [[YapDatabaseRelationshipEdge alloc] initWithName:name
	                                               sourceKey:sourceKey
	                                              collection:sourceCollection
	                                      destinationFileURL:destinationFileURL
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
- (id)initWithName:(NSString *)inName destinationFileURL:(NSURL *)dstFileURL
                                         nodeDeleteRules:(YDB_NodeDeleteRules)rules
{
	if (inName == nil) return nil;     // Edge requires name
	if (dstFileURL == nil) return nil; // Edge requires destination
	
	if ((self = [super init]))
	{
		name = [inName copy];
		
		destinationFileURL = [dstFileURL copy];
		
		nodeDeleteRules = rules;
		isManualEdge = NO;
		
		state = YDB_EdgeState_DestinationFileURL   | // originally created with valid dstFileURL
		        YDB_EdgeState_HasDestinationRowid  | // no need for destinationRowid lookup (doesn't apply)
		        YDB_EdgeState_HasDestinationFileURL; // no need for destinationFileURL deserialization
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
                             destinationFileURL:(NSURL *)dstFileURL
                                nodeDeleteRules:(YDB_NodeDeleteRules)rules
{
	if (inName == nil) return nil;     // Edge requires name
	if (srcKey == nil) return nil;     // Edge requires source
	if (dstFileURL == nil) return nil; // Edge requires destination
	
	if ((self = [super init]))
	{
		name = [inName copy];
		
		sourceKey = [srcKey copy];
		sourceCollection = srcCollection ? [srcCollection copy] : @"";
		
		destinationFileURL = [dstFileURL copy];
		
		nodeDeleteRules = rules;
		isManualEdge = YES;
		
		state = YDB_EdgeState_DestinationFileURL   | // originally created with valid dstFileURL
		        YDB_EdgeState_HasDestinationRowid  | // no need for destinationRowid lookup (doesn't apply)
		        YDB_EdgeState_HasDestinationFileURL; // no need for destinationFileURL deserialization
	}
	return self;
}

/**
 * Internal init method.
 * This method is used when reading an edge from a row in the database.
**/
- (id)initWithEdgeRowid:(int64_t)rowid
                   name:(NSString *)inName
               srcRowid:(int64_t)srcRowid
               dstRowid:(int64_t)dstRowid
                dstData:(NSData *)dstData
                  rules:(int)rules
                 manual:(BOOL)manual
{
	if ((self = [super init]))
	{
		name = [inName copy];
		destinationFileURLData = dstData;
		nodeDeleteRules = (unsigned short)rules;
		isManualEdge = manual;
		
		edgeRowid = rowid;
		sourceRowid = srcRowid;
		destinationRowid = dstRowid;
		
		state = YDB_EdgeState_HasEdgeRowid | YDB_EdgeState_HasSourceRowid | YDB_EdgeState_HasDestinationRowid;
		
		if (destinationFileURLData)
			state |= YDB_EdgeState_DestinationFileURL; // originally created with valid dstFileURL
	}
	return self;
}

#pragma mark NSCopying

- (id)copyWithZone:(NSZone __unused *)zone
{
	YapDatabaseRelationshipEdge *copy = [[YapDatabaseRelationshipEdge alloc] init];
	
	copy->name = name;
	copy->sourceKey = sourceKey;
	copy->sourceCollection = sourceCollection;
	copy->destinationKey = destinationKey;
	copy->destinationCollection = destinationCollection;
	copy->destinationFileURL = destinationFileURL;
	copy->nodeDeleteRules = nodeDeleteRules;
	copy->isManualEdge = isManualEdge;
	
	copy->edgeRowid = edgeRowid;
	copy->sourceRowid = sourceRowid;
	copy->destinationRowid = destinationRowid;
	
	copy->destinationFileURLData = destinationFileURLData;
	
	copy->state = state;                // State remains - related to ivar state
	copy->flags = YDB_EdgeFlags_None;   // Flags reset - related to particular instance
	copy->action = YDB_EdgeAction_None; // Action reset - related to particular instance
	
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
	copy->destinationFileURL = destinationFileURL;
	copy->nodeDeleteRules = nodeDeleteRules;
	copy->isManualEdge = isManualEdge;
	
	copy->edgeRowid = edgeRowid;
	copy->sourceRowid = newSrcRowid;
	copy->destinationRowid = destinationRowid;
	
	copy->destinationFileURLData = destinationFileURLData;
	
	copy->state = state;                // State remains - related to ivar state
	copy->flags = YDB_EdgeFlags_None;   // Flags reset - related to particular instance
	copy->action = YDB_EdgeAction_None; // Action reset - related to particular instance
	
	// Ensure HasSourceRowid is set due to the change
	copy->state |= YDB_EdgeState_HasSourceRowid;
	
	return copy;
}

#pragma mark Info

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
	
	// Create state string
	
	NSMutableString *stateStr = [NSMutableString stringWithCapacity:64];
	
	if (state & YDB_EdgeState_DestinationFileURL)
		[stateStr appendString:@"DestinationFileURL, "];
	
	if (state & YDB_EdgeState_HasSourceRowid)
		[stateStr appendString:@"HasSourceRowid, "];
	
	if (state & YDB_EdgeState_HasDestinationRowid)
		[stateStr appendString:@"HasDestinationRowid, "];
	
	if (state & YDB_EdgeState_HasDestinationFileURL)
		[stateStr appendString:@"HasDestinationFileURL, "];
	
	if (state & YDB_EdgeState_HasEdgeRowid)
		[stateStr appendString:@"HasEdgeRowid, "];
	
	if ([stateStr length] > 0)
		[stateStr deleteCharactersInRange:NSMakeRange([stateStr length] - 2, 2)];
	
	// Create flags string
	
	NSMutableString *flagsStr = [NSMutableString stringWithCapacity:64];
	
	if (flags & YDB_EdgeFlags_SourceDeleted)
		[flagsStr appendString:@"SourceDeleted, "];
	
	if (flags & YDB_EdgeFlags_DestinationDeleted)
		[flagsStr appendString:@"DestinationDeleted, "];
	
	if (flags & YDB_EdgeFlags_BadSource)
		[flagsStr appendString:@"BadSource, "];
	
	if (flags & YDB_EdgeFlags_BadDestination)
		[flagsStr appendString:@"BadDestination, "];
	
	if (flags & YDB_EdgeFlags_EdgeNotInDatabase)
		[flagsStr appendString:@"EdgeNotInDatabase, "];
	
	if ([flagsStr length] > 0)
		[flagsStr deleteCharactersInRange:NSMakeRange([flagsStr length] - 2, 2)];
	
	// Create action string

	NSString *actionStr = @"";
	
	if (action == YDB_EdgeAction_None)
		actionStr = @"none";
	else if (action == YDB_EdgeAction_Insert)
		actionStr = @"insert";
	else if (action == YDB_EdgeAction_Update)
		actionStr = @"update";
	else if (action == YDB_EdgeAction_Delete)
		actionStr = @"delete";
	
	// Create full edge description
	
	NSMutableString *description = [NSMutableString stringWithCapacity:128];
	
	[description appendFormat:@"<YapDatabaseRelationshipEdge[%p]", self];
	[description appendFormat:@" name(%@)", name];
	
	if (sourceKey)
		[description appendFormat:@" src(%@, %@)", sourceKey, (sourceCollection ?: @"")];
	else if (state & YDB_EdgeState_HasSourceRowid)
		[description appendFormat:@" srcRowid(%lld)", sourceRowid];
	
	if (destinationKey)
		[description appendFormat:@" dst(%@, %@)", destinationKey, (destinationCollection ?: @"")];
	else if (state & YDB_EdgeState_DestinationFileURL)
	{
		if (state & YDB_EdgeState_HasDestinationFileURL)
			[description appendFormat:@" dstFileURL(%@)", destinationFileURL];
		else
			[description appendFormat:@" dstFileURL(<not deserialized>)"];
	}
	else if (state & YDB_EdgeState_HasDestinationRowid)
		[description appendFormat:@" dstRowid(%lld)", destinationRowid];
	
	[description appendFormat:@" rules(%@)", rulesStr];
	
	if ([stateStr length] > 0) {
		[description appendFormat:@" state(%@)", stateStr];
	}
	
	if ([flagsStr length] > 0) {
		[description appendFormat:@" flags(%@)", flagsStr];
	}
	
	if ([actionStr length] > 0) {
		[description appendFormat:@" action(%@)", actionStr];
	}
	
	if (isManualEdge) {
		[description appendString:@" manual"];
	}
	
	[description appendString:@">"];
	
	return description;
}

@end
