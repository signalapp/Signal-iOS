/**
 * Copyright Deusty LLC.
**/

#import "YapDatabaseCloudCoreOperation.h"
#import "YapDatabaseCloudCoreOperationPrivate.h"
#import "YapDatabaseCloudCorePipeline.h"
#import "YapDatabaseCloudCore.h"
#import "YapDatabaseLogging.h"

/**
 * Define log level for this file: OFF, ERROR, WARN, INFO, VERBOSE
 * See YapDatabaseLogging.h for more information.
 **/
#if DEBUG
  static const int ydbLogLevel = YDB_LOG_LEVEL_VERBOSE | YDB_LOG_FLAG_TRACE;
#else
  static const int ydbLogLevel = YDB_LOG_LEVEL_WARN;
#endif
#pragma unused(ydbLogLevel)

static int const kYapDatabaseCloudCoreOperation_CurrentVersion = 1;
#pragma unused(kYapDatabaseCloudCoreOperation_CurrentVersion)

static NSString *const k_version            = @"version_base"; // subclasses should use version_XXX
static NSString *const k_uuid               = @"uuid";
static NSString *const k_priority           = @"priority";
static NSString *const k_dependencies       = @"dependencies";
static NSString *const k_persistentUserInfo = @"persistentUserInfo";


NSString *const YDBCloudCoreOperationIsReadyToStartNotification = @"YDBCloudCoreOperationIsReadyToStart";


@implementation YapDatabaseCloudCoreOperation

// Private properties

@synthesize operationRowid = operationRowid;

@synthesize needsDeleteDatabaseRow = needsDeleteDatabaseRow;
@synthesize needsModifyDatabaseRow = needsModifyDatabaseRow;

@synthesize pendingStatus = pendingStatus;

// Public properties

@synthesize uuid = uuid;
@synthesize pipeline = pipeline;
@synthesize priority = priority;
@synthesize dependencies = dependencies;
@synthesize persistentUserInfo = persistentUserInfo;

/**
 * Make sure all your subclasses call this method ([super init]).
**/
- (instancetype)init
{
	if ((self = [super init]))
	{
		uuid = [NSUUID UUID];
	}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSCoding
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (instancetype)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super init]))
	{
		int version = [decoder decodeIntForKey:k_version];
		
		// The pipeline property is NOT encoded.
		// It's stored via the pipelineID column automatically,
		// and is explicitly set when the operations are restored.
		
		uuid = [decoder decodeObjectForKey:k_uuid];
		priority = [decoder decodeInt32ForKey:k_priority];
		
		if (version == 0)
		{
			// In versions < 1, dependencies was stored as an array.
			
			NSArray *dependenciesArray = [decoder decodeObjectForKey:k_dependencies];
			if (dependenciesArray) {
				dependencies = [NSSet setWithArray:dependenciesArray];
			}
		}
		else
		{
			dependencies = [decoder decodeObjectForKey:k_dependencies];
		}
		
		persistentUserInfo = [decoder decodeObjectForKey:k_persistentUserInfo];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	if (kYapDatabaseCloudCoreOperation_CurrentVersion != 0) {
		[coder encodeInt:kYapDatabaseCloudCoreOperation_CurrentVersion forKey:k_version];
	}
	
	// The pipeline property is NOT encoded.
	// It's stored via the pipelineID column automatically,
	// and is explicitly set when the operations are restored.
	
	[coder encodeObject:uuid forKey:k_uuid];
	[coder encodeInt32:priority forKey:k_priority];
	[coder encodeObject:dependencies forKey:k_dependencies];
	
	[coder encodeObject:persistentUserInfo forKey:k_persistentUserInfo];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSCopying
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (instancetype)copyWithZone:(NSZone *)zone
{
	YapDatabaseCloudCoreOperation *copy = [[[self class] alloc] init];
	
	copy->uuid = uuid;
	copy->pipeline = pipeline;
	copy->dependencies = dependencies;
	copy->priority = priority;
	copy->persistentUserInfo = persistentUserInfo;
	
	copy->operationRowid = operationRowid;
	copy->needsDeleteDatabaseRow = needsDeleteDatabaseRow;
	copy->needsModifyDatabaseRow = needsModifyDatabaseRow;
	copy->pendingStatus = pendingStatus;
	
	return copy;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Public API
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)setDependencies:(NSSet<NSUUID *> *)newDependencies
{
#if !defined(NS_BLOCK_ASSERTIONS)
	for (id obj in newDependencies)
	{
		NSAssert([obj isKindOfClass:[NSUUID class]], @"Bad dependecy object !");
	}
#endif
	
	NSString *const propKey = NSStringFromSelector(@selector(dependencies));
	
	[self willChangeValueForKey:propKey];
	{
		dependencies = [newDependencies copy];
	}
	[self didChangeValueForKey:propKey];
}

- (void)addDependency:(id)dependency
{
	if (dependency == nil) return;
		
	NSUUID *dependencyUUID = nil;
	
	if ([dependency isKindOfClass:[NSUUID class]])
	{
		dependencyUUID = (NSUUID *)dependency;
	}
	else if ([dependency isKindOfClass:[YapDatabaseCloudCoreOperation class]])
	{
		dependencyUUID = [(YapDatabaseCloudCoreOperation *)dependency uuid];
	}
	
	NSAssert(dependencyUUID != nil, @"Bad dependecy object !");
	
	NSString *const propKey = NSStringFromSelector(@selector(dependencies));
	
	[self willChangeValueForKey:propKey];
	{
		if (dependencies == nil)
			dependencies = [NSSet setWithObject:dependencyUUID];
		else
			dependencies = [dependencies setByAddingObject:dependencyUUID];
	}
	[self didChangeValueForKey:propKey];
}

/**
 * Convenience method for modifying the persistentUserInfo dictionary.
**/
- (void)setPersistentUserInfoObject:(id)userInfoObject forKey:(NSString *)userInfoKey
{
	if (userInfoKey == nil) return;
	
	NSString *const propKey = NSStringFromSelector(@selector(persistentUserInfo));
	
	[self willChangeValueForKey:propKey];
	{
		if (persistentUserInfo == nil)
		{
			if (userInfoObject)
				persistentUserInfo = @{ userInfoKey : userInfoObject };
		}
		else
		{
			NSMutableDictionary *newPersistentUserInfo = [persistentUserInfo mutableCopy];
			
			if (userInfoObject)
				[newPersistentUserInfo setObject:userInfoObject forKey:userInfoKey];
			else
				[newPersistentUserInfo removeObjectForKey:userInfoKey];
			
			persistentUserInfo = [newPersistentUserInfo copy];
		}
	}
	[self didChangeValueForKey:propKey];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Protected API
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Subclasses may choose to calculate implicit dependencies.
 *
 * This method is designed to assist in such a process,
 * as it allows for easier separation between:
 * - explict dependencies (specified by the user)
 * - implicit dependencies (calculated by the subclass)
 *
 * The default implementation simply returns the `dependencies` property.
**/
- (NSSet<NSUUID *> *)dependencyUUIDs
{
	return dependencies;
}

- (BOOL)pendingStatusIsSkippedOrCompleted
{
	if (pendingStatus)
	{
		YDBCloudCoreOperationStatus status = (YDBCloudCoreOperationStatus)[pendingStatus integerValue];
		
		return (status == YDBCloudOperationStatus_Skipped || status == YDBCloudOperationStatus_Completed);
	}
	else
	{
		return NO;
	}
}

- (BOOL)pendingStatusIsCompleted
{
	if (pendingStatus)
		return ([pendingStatus integerValue] == YDBCloudOperationStatus_Completed);
	else
		return NO;
}

- (BOOL)pendingStatusIsSkipped
{
	if (pendingStatus)
		return ([pendingStatus integerValue] == YDBCloudOperationStatus_Skipped);
	else
		return NO;
}

/**
 * Subclasses can override me if they add custom transaction specific variables.
**/
- (void)clearTransactionVariables
{
	needsDeleteDatabaseRow = NO;
	needsModifyDatabaseRow = NO;
	pendingStatus = nil;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Equality
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)isEqual:(id)object
{
	if ([object isKindOfClass:[YapDatabaseCloudCoreOperation class]])
		return [self isEqualToOperation:(YapDatabaseCloudCoreOperation *)object];
	else
		return NO;
}

/**
 * Subclasses should override this method, and add their own comparisons.
**/
- (BOOL)isEqualToOperation:(YapDatabaseCloudCoreOperation *)op
{
	if (operationRowid != op->operationRowid) return NO;
	
	if (needsDeleteDatabaseRow != op->needsDeleteDatabaseRow) return NO;
	if (needsModifyDatabaseRow != op->needsModifyDatabaseRow) return NO;
	
	if (!YDB_IsEqualOrBothNil(pendingStatus, op->pendingStatus)) return NO;
	
	if (!YDB_IsEqualOrBothNil(uuid, op->uuid)) return NO;
	if (!YDB_IsEqualOrBothNil(pipeline, op->pipeline)) return NO;
	
	if (priority != op->priority) return NO;
	
	if (!YDB_IsEqualOrBothNil(dependencies, op->dependencies)) return NO;
	if (!YDB_IsEqualOrBothNil(persistentUserInfo, op->persistentUserInfo)) return NO;
	
	return YES;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark General
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)debugDescription
{
	if (!pipeline || [pipeline isEqualToString:YapDatabaseCloudCoreDefaultPipelineName])
	{
		return [NSString stringWithFormat:@"<YapDatabaseCloudCoreOperation[%p]: uuid=\"%@\", priority=%d>",
		                                     self, uuid, priority];
	}
	else
	{
		return [NSString stringWithFormat:@"<YapDatabaseCloudCoreOperation[%p]: pipeline=\"%@\" uuid=\"%@\", priority=%d>",
		                                     self, pipeline, uuid, priority];
	}
}

@end
