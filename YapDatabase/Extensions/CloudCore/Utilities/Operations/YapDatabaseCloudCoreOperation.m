/**
 * Copyright Deusty LLC.
**/

#import "YapDatabaseCloudCoreOperation.h"
#import "YapDatabaseCloudCoreOperationPrivate.h"
#import "YapDatabaseCloudCorePipeline.h"
#import "YapDatabaseLogging.h"

#import <objc/runtime.h>
#import <libkern/OSAtomic.h>

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


@implementation YapDatabaseCloudCoreOperation {
@private
	
	int32_t isImported;
}

// Private properties

@synthesize operationRowid = operationRowid;

@synthesize needsDeleteDatabaseRow = needsDeleteDatabaseRow;
@synthesize needsModifyDatabaseRow = needsModifyDatabaseRow;

@synthesize pendingStatus = pendingStatus;

@synthesize isImmutable = isImmutable;
@dynamic hasChanges;

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
		
		// Turn on KVO for object.
		// We do this so we can get notified if the user is about to make changes to one of the object's properties.
		//
		// Don't worry, this doesn't create a retain cycle.
		
		[self addObserver:self forKeyPath:@"isImmutable" options:0 context:NULL];
	}
	return self;
}

- (void)dealloc
{
	[self removeObserver:self forKeyPath:@"isImmutable" context:NULL];
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
		
		// Turn on KVO for object.
		// We do this so we can get notified if the user is about to make changes to one of the object's properties.
		//
		// Don't worry, this doesn't create a retain cycle.
		
		[self addObserver:self forKeyPath:@"isImmutable" options:0 context:NULL];
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
	copy->isImported = self.isImported ? 1 : 0;
	copy->changedProperties = [changedProperties mutableCopy];
	
	copy->operationRowid = operationRowid;
	copy->needsDeleteDatabaseRow = needsDeleteDatabaseRow;
	copy->needsModifyDatabaseRow = needsModifyDatabaseRow;
	copy->pendingStatus = pendingStatus;
	
	copy->uuid = uuid;
	copy->pipeline = pipeline;
	copy->dependencies = dependencies;
	copy->priority = priority;
	copy->persistentUserInfo = persistentUserInfo;
	
	return copy;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Import
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)import:(YapDatabaseCloudCoreOptions *)options
{
	const int32_t oldValue = 0;
	const int32_t newValue = 1;
	
	return OSAtomicCompareAndSwap32(oldValue, newValue, &isImported);
}

- (BOOL)isImported
{
	int32_t value = OSAtomicAdd32(0, &isImported);
	return (value != 0);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Public API
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)setDependencies:(NSArray *)newDependencies
{
	if (![self validateDependencies:newDependencies]) return;
	
	NSString *const propKey = NSStringFromSelector(@selector(dependencies));
	
	// Do NOT remove this line of code !
	//
	// If you're getting an exception, that means you're attempting to mutate an operation
	// AFTER you've already passed it to YapDatabaseCloudCore. This mutation is unsupported,
	// and the exception is here to help you address the root cause of the problem.
	//
	[self willChangeValueForKey:propKey];
	{
		dependencies = [newDependencies copy];
	}
	[self didChangeValueForKey:propKey];
}

- (void)addDependency:(id)dependency
{
	if (dependency == nil) return;
	
	if ([dependency isKindOfClass:[YapDatabaseCloudCoreOperation class]])
	{
		// Auto fix common mistake
		[self addDependency:[(YapDatabaseCloudCoreOperation *)dependency uuid]];
		return;
	}
	
	if (![self validateDependencies:@[ dependency ]]) return;
	
	NSString *const propKey = NSStringFromSelector(@selector(dependencies));
	
	// Do NOT remove this line of code !
	//
	// If you're getting an exception, that means you're attempting to mutate an operation
	// AFTER you've already passed it to YapDatabaseCloudCore. This mutation is unsupported,
	// and the exception is here to help you address the root cause of the problem.
	//
	[self willChangeValueForKey:propKey];
	{
		if (dependencies == nil)
			dependencies = [NSSet setWithObject:dependency];
		else
			dependencies = [dependencies setByAddingObject:dependency];
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
	
	// Do NOT remove this line of code !
	//
	// If you're getting an exception, that means you're attempting to mutate an operation in an unsupported way.
	// The exception is here to help you address the root cause of the problem.
	//
	// So why the exception ?
	//
	// The 'persistentUserInfo' dictionary is designed to be persisted to the database.
	// Thus you cannot simply change it whenever you want. You need to change it in such a manner
	// that the new value can be persisted to the database (updating the old value).
	//
	// When you first hand the operation to YapDatabaseCloudCore, it makes the operation instance immutable.
	// This is done to make it explicit that changes to persistent properties can no longer be
	// performed on the original instance.  So if you want to change a persistent property at any later point in time,
	// you need to clone the original operation, modify the clone, and then hand the clone to YapDatabaseCloudCore
	// so that it can persist the changes you've made.
	//
	// For example:
	//
	// YapDatabaseCloudCore *clone = [operation mutableClone];
	// [clone setPersistentUserInfoObject:obj forKey:key];
	//
	// [databaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
	//
	//     [[transaction ext:@"MyCloud"] modifyOperation:clone];
	// }];
	//
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

/**
 * Abstract property.
 * Designed to be overriden by subclasses.
**/
- (NSString *)attachCloudURI
{
	NSAssert(NO, @"Missing required override method: %@", NSStringFromSelector(_cmd));
	return nil;
}

/**
 * Abstract property.
 * Designed to be overriden by subclasses.
**/
- (NSSet *)dependencyUUIDs
{
	NSAssert(NO, @"Missing required override method: %@", NSStringFromSelector(_cmd));
	return nil;
}

/**
 * This method can be override in order to enforce which type of dependencies are valid.
 * For example, are the following classes ok to add to the dependencies array:
 *  - uuid
 *  - string
 *  - url
 *  - CKRecordID
 * 
 * The answer is rather domain dependent, and thus this override provide the opportunity to enforce policy.
**/
- (BOOL)validateDependencies:(NSArray *)inputDependencies
{
	// Override me to support more classes besides just NSUUID
	
	for (id dependency in inputDependencies)
	{
		if (![dependency isKindOfClass:[NSUUID class]])
		{
			YDBLogError(@"Invalid dependencies: Bad class: %@", [dependency class]);
			return NO;
		}
	}
	
	return YES;
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
#pragma mark Immutability
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Subclasses should override and add properties that shouldn't be changed after
 * the operation has been marked immutable.
**/
+ (NSMutableSet *)monitoredProperties
{
	NSMutableSet *properties = [NSMutableSet setWithCapacity:8];
	
	[properties addObject:NSStringFromSelector(@selector(uuid))];
	[properties addObject:NSStringFromSelector(@selector(pipeline))];
	[properties addObject:NSStringFromSelector(@selector(dependencies))];
	[properties addObject:NSStringFromSelector(@selector(priority))];
	[properties addObject:NSStringFromSelector(@selector(persistentUserInfo))];
	
	return properties;
}


+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)key
{
	if ([key isEqualToString:NSStringFromSelector(@selector(isImmutable))])
		return YES;
	else
		return [super automaticallyNotifiesObserversForKey:key];
}

+ (NSSet *)keyPathsForValuesAffectingIsImmutable
{
	// In order for the KVO magic to work, we specify that the isImmutable property is dependent
	// upon all other properties in the class that should become immutable.
	
	return [self monitoredProperties];
}

- (void)makeImmutable
{
	if (!isImmutable)
	{
		// Set immutable flag
		isImmutable = YES;
		changedProperties = nil;
	}
}

- (void)observeValueForKeyPath:(NSString *)keyPath
					  ofObject:(id)object
						change:(NSDictionary *)change
					   context:(void *)context
{
	// Nothing to do (but method is required to exist)
}

- (void)willChangeValueForKey:(NSString *)key
{
	if (isImmutable)
	{
		if ([[[self class] monitoredProperties] containsObject:key])
		{
			@throw [self immutableException:key];
		}
	}
	
	[super willChangeValueForKey:key];
}

- (void)didChangeValueForKey:(NSString *)key
{
	if (changedProperties == nil)
		changedProperties = [[NSMutableSet alloc] init];
	
	[changedProperties addObject:key];
	
	[super didChangeValueForKey:key];
}

- (BOOL)hasChanges
{
	return (changedProperties.count > 0);
}

- (NSException *)immutableException:(NSString *)key
{
	NSString *reason;
	if (key)
		reason = [NSString stringWithFormat:
		    @"Attempting to mutate YapDatabaseCloudCoreOperation object in a non-supported way."
		    @" Class = %@, property = %@", NSStringFromClass([self class]), key];
	else
		reason = [NSString stringWithFormat:
		    @"Attempting to mutate YapDatabaseCloudCoreOperation object in a non-supported way."
		    @" Class = %@", NSStringFromClass([self class])];
	
	NSString *moreInfo = [NSString stringWithFormat:
	    @"Persistent properties of the operation become immutable once the operation has been"
	    @" given to YapDatabaseCloudCore. To modify these persistent properties, you need to copy the operation,"
	    @" modify the copy, and then hand the copy to YapDatabaseCloudCore via the modifyOperation method."
	    @" This applies to the following properties: %@",
	    [[self class] monitoredProperties]];
	
	NSDictionary *suggestion = @{ NSLocalizedRecoverySuggestionErrorKey: moreInfo };
	
	return [NSException exceptionWithName:@"YapDatabaseCloudCoreOperationException" reason:reason userInfo:suggestion];
}

@end
