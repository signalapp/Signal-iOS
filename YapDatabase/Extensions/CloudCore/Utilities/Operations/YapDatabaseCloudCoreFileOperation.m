/**
 * Copyright Deusty LLC.
**/

#import "YapDatabaseCloudCoreFileOperation.h"
#import "YapDatabaseCloudCoreOperationPrivate.h"
#import "YapDatabaseLogging.h"

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

/* extern */ NSString *const YDBCloudOperationType_Upload    = @"Upload";
/* extern */ NSString *const YDBCloudOperationType_Delete    = @"Delete";
/* extern */ NSString *const YDBCloudOperationType_Move      = @"Move";
/* extern */ NSString *const YDBCloudOperationType_Copy      = @"Copy";
/* extern */ NSString *const YDBCloudOperationType_CreateDir = @"CreateDir";

static int const kYapDatabaseCloudCoreFileOperation_CurrentVersion = 0;
#pragma unused(kYapDatabaseCloudCoreFileOperation_CurrentVersion)

static NSString *const k_version             = @"version_file"; // subclasses should use version_XXX
static NSString *const k_type                = @"type";
static NSString *const k_cloudPath           = @"cloudPath";
static NSString *const k_targetCloudPath     = @"targetCloudPath";
static NSString *const k_shouldAttach        = @"shouldAttach";
static NSString *const k_dependencyUUIDs     = @"dependencyUUIDs";


@implementation YapDatabaseCloudCoreFileOperation {
@private
	
	NSSet *dependencyUUIDs;
}

@synthesize type = type;
@synthesize cloudPath = cloudPath;
@synthesize targetCloudPath = targetCloudPath;
@synthesize shouldAttach = shouldAttach;

@dynamic name;

- (BOOL)isUploadOperation
{
	return [type isEqualToString:YDBCloudOperationType_Upload];
}

- (BOOL)isDeleteOperation
{
	return [type isEqualToString:YDBCloudOperationType_Delete];
}

- (BOOL)isMoveOperation
{
	return [type isEqualToString:YDBCloudOperationType_Move];
}

- (BOOL)isCopyOperation
{
	return [type isEqualToString:YDBCloudOperationType_Copy];
}

- (BOOL)isCreateDirOperation
{
	return [type isEqualToString:YDBCloudOperationType_CreateDir];
}

- (BOOL)isCustomOperation
{
	return ![type isEqualToString:YDBCloudOperationType_Upload]
	    && ![type isEqualToString:YDBCloudOperationType_Delete]
	    && ![type isEqualToString:YDBCloudOperationType_Move]
	    && ![type isEqualToString:YDBCloudOperationType_Copy]
	    && ![type isEqualToString:YDBCloudOperationType_CreateDir];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Creation
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

+ (YapDatabaseCloudCoreFileOperation *)uploadWithCloudPath:(YapFilePath *)cloudPath
{
	return [[YapDatabaseCloudCoreFileOperation alloc] initWithType:YDBCloudOperationType_Upload
	                                                     cloudPath:cloudPath
	                                               targetCloudPath:nil];
}

+ (YapDatabaseCloudCoreFileOperation *)deleteWithCloudPath:(YapFilePath *)cloudPath
{
	return [[YapDatabaseCloudCoreFileOperation alloc] initWithType:YDBCloudOperationType_Delete
	                                                     cloudPath:cloudPath
	                                               targetCloudPath:nil];
}

+ (YapDatabaseCloudCoreFileOperation *)moveWithCloudPath:(YapFilePath *)sourcePath
                                         targetCloudPath:(YapFilePath *)targetPath
{
	return [[YapDatabaseCloudCoreFileOperation alloc] initWithType:YDBCloudOperationType_Move
	                                                     cloudPath:sourcePath
	                                               targetCloudPath:targetPath];
}

+ (YapDatabaseCloudCoreFileOperation *)copyWithCloudPath:(YapFilePath *)sourcePath
                                         targetCloudPath:(YapFilePath *)targetPath
{
	return [[YapDatabaseCloudCoreFileOperation alloc] initWithType:YDBCloudOperationType_Copy
	                                                     cloudPath:sourcePath
	                                               targetCloudPath:targetPath];
}

+ (YapDatabaseCloudCoreFileOperation *)createDirectoryWithCloudPath:(YapFilePath *)cloudPath
{
	return [[YapDatabaseCloudCoreFileOperation alloc] initWithType:YDBCloudOperationType_CreateDir
	                                                     cloudPath:cloudPath
	                                               targetCloudPath:nil];
}

+ (YapDatabaseCloudCoreFileOperation *)operationWithType:(NSString *)type cloudPath:(YapFilePath *)cloudPath
{
	return [[YapDatabaseCloudCoreFileOperation alloc] initWithType:type
	                                                     cloudPath:cloudPath
	                                               targetCloudPath:nil];

}

+ (YapDatabaseCloudCoreFileOperation *)operationWithType:(NSString *)type
                                               cloudPath:(YapFilePath *)cloudPath
                                         targetCloudPath:(YapFilePath *)targetCloudPath
{
	return [[YapDatabaseCloudCoreFileOperation alloc] initWithType:type
	                                                     cloudPath:cloudPath
	                                               targetCloudPath:targetCloudPath];
}

- (instancetype)initWithType:(NSString *)inType
                   cloudPath:(YapFilePath *)inCloudPath
             targetCloudPath:(YapFilePath *)inTargetCloudPath
{
	NSString *_type               = [inType copy];            // mutable string protection
	YapFilePath *_cloudPath       = [inCloudPath copy];       // Defense against mutable subclasses
	YapFilePath *_targetCloudPath = [inTargetCloudPath copy]; // Defense against mutable subclasses
	
	if (_type == nil)      return nil; // required parameter
	if (_cloudPath == nil) return nil; // required parameter
	
	if ([_type isEqualToString:YDBCloudOperationType_Move] || [_type isEqualToString:YDBCloudOperationType_Copy])
	{
		if (_targetCloudPath == nil)
			return nil; // required for move/copy operation
	}
	
	if ((self = [super init]))
	{
		type = _type;
		cloudPath = _cloudPath;
		targetCloudPath = _targetCloudPath;
	}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Names
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

+ (NSString *)nameForUploadWithCloudPath:(YapFilePath *)cloudPath
{
	return [self nameForType:YDBCloudOperationType_Upload
	               cloudPath:cloudPath
	         targetCloudPath:nil];
}

+ (NSString *)nameForDeleteWithCloudPath:(YapFilePath *)cloudPath
{
	return [self nameForType:YDBCloudOperationType_Delete
	               cloudPath:cloudPath
	         targetCloudPath:nil];
}

+ (NSString *)nameForMoveWithCloudPath:(YapFilePath *)cloudPath targetCloudPath:(YapFilePath *)targetCloudPath
{
	return [self nameForType:YDBCloudOperationType_Move
	               cloudPath:cloudPath
	         targetCloudPath:targetCloudPath];
}

+ (NSString *)nameForCopyWithCloudPath:(YapFilePath *)cloudPath targetCloudPath:(YapFilePath *)targetCloudPath
{
	return [self nameForType:YDBCloudOperationType_Copy
	               cloudPath:cloudPath
	         targetCloudPath:targetCloudPath];
}

+ (NSString *)nameForType:(NSString *)type cloudPath:(YapFilePath *)cloudPath
{
	return [self nameForType:type
	               cloudPath:cloudPath
	         targetCloudPath:nil];
}

+ (NSString *)nameForType:(NSString *)type
                cloudPath:(YapFilePath *)cloudPath
          targetCloudPath:(YapFilePath *)targetCloudPath
{
	if (targetCloudPath)
		return [NSString stringWithFormat:@"%@ %@ -> %@", (type ?: @""), cloudPath.path, targetCloudPath.path];
	else
		return [NSString stringWithFormat:@"%@ %@", (type ?: @""), cloudPath.path];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSCoding
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (instancetype)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super initWithCoder:decoder]))
	{
		type = [decoder decodeObjectForKey:k_type];
		cloudPath = [decoder decodeObjectForKey:k_cloudPath];
		targetCloudPath = [decoder decodeObjectForKey:k_targetCloudPath];
		shouldAttach = [decoder decodeObjectForKey:k_shouldAttach];
		dependencyUUIDs = [decoder decodeObjectForKey:k_dependencyUUIDs];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	[super encodeWithCoder:coder];
	
	if (kYapDatabaseCloudCoreFileOperation_CurrentVersion != 0) {
		[coder encodeInt:kYapDatabaseCloudCoreFileOperation_CurrentVersion forKey:k_version];
	}
	
	[coder encodeObject:type forKey:k_type];
	[coder encodeObject:cloudPath forKey:k_cloudPath];
	[coder encodeObject:targetCloudPath forKey:k_targetCloudPath];
	[coder encodeObject:shouldAttach forKey:k_shouldAttach];
	[coder encodeObject:dependencyUUIDs forKey:k_dependencyUUIDs];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSCopying
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (instancetype)copyWithZone:(NSZone *)zone
{
	YapDatabaseCloudCoreFileOperation *copy = [super copyWithZone:zone];
	
	copy->type = type;
	copy->cloudPath = cloudPath;
	copy->targetCloudPath = targetCloudPath;
	copy->shouldAttach = shouldAttach;
	
	copy->dependencyUUIDs = [dependencyUUIDs mutableCopy];
	
	return copy;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Properties
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Every operation has a name which is derived from the operation's attributes.
 * Specifically, the name is derived as follows:
 *
 * if (targetCloudPath)
 *   [NSString stringWithFormat@"%@ %@ -> %@", type, cloudPath, targetCloudPath];
 * else
 *   [NSString stringWithFormat@"%@ %@", type, cloudPath];
 *
 * Names are designed to assist with dependencies.
 *
 * For example, suppose you have 2 operations: opA & opB
 * You want opB to depend on opA, so that opA comletes before opB starts.
 * There are 2 ways in which you can accomplish this:
 *
 * 1. [opB addDependency:opA.uuid]
 * 2. [opB addDependency:opA.name]
 *
 * Option 1 is always the preferred method, but is only convenient if you happen to have the opB instance
 * sitting around.
 *
 * Option 2 can easily be generated even without opB, by simply using the various class name methods.
 * - [YapDatabaseCloudCoreFileOperation nameForUploadWithCloudPath:]
 * - [YapDatabaseCloudCoreFileOperation nameForDeleteWithCloudPath:]
 * - [YapDatabaseCloudCoreFileOperation nameForMoveWithCloudPath:targetCloudPath:]
 * - [YapDatabaseCloudCoreFileOperation nameForCopyWithCloudPath:targetCloudPath:]
 * - [YapDatabaseCloudCoreFileOperation nameForType:cloudPath:]
 * - [YapDatabaseCloudCoreFileOperation nameForType:cloudPath:targetCloudPath:]
**/
- (NSString *)name
{
	return [[self class] nameForType:type cloudPath:cloudPath targetCloudPath:targetCloudPath];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark General
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)isOperationType:(NSString *)inType
{
	return [type isEqualToString:inType];
}

- (NSString *)description
{
	if (targetCloudPath)
		return [NSString stringWithFormat:@"<%@[%p] %@: %@ -> %@>",
		                                   [self class], self, (type ?: @""), cloudPath.path, targetCloudPath.path];
	else if (cloudPath)
		return [NSString stringWithFormat:@"<%@[%p] %@: %@>",
		                                   [self class], self, (type ?: @""), cloudPath.path];
	else
		return [NSString stringWithFormat:@"<%@[%p] %@>",
		                                   [self class], self, (type ?: @"")];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Subclass API
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * An operation can be imported once, and only once.
 * This thread-safe method will only return YES the very first time it's called.
 * This helps ensure the same operation instance isn't mistakenly submitted multiple times.
 *
 * Subclasses may optionally override this method to do something with the options parameter.
 * Subclasses must invoke [super import:], and pay attention to the return value.
**/
- (BOOL)import:(YapDatabaseCloudCoreOptions *)options
{
	BOOL result = [super import:options];
	if (result)
	{
		implicitAttach = options.implicitAttach;
	}
	
	return result;
}

/**
 * Subclasses MUST override this method.
 *
 * Represents the cloudURI to use if attaching the collection/key tuple.
 *
 * This property is abstract, and must be overriden by subclasses to return a value.
 * This property is optional.
 * If a non-nil value is returned, the cloudURI will be attached to the collection/key tuple.
 * If a nil value is returned, no attaching will occur.
**/
- (NSString *)attachCloudURI
{
	if (shouldAttach)
	{
		if (shouldAttach.boolValue)
		{
			return cloudPath.path;
		}
	}
	else if (implicitAttach)
	{
		if ([type isEqualToString:YDBCloudOperationType_Upload]   ||
		    [type isEqualToString:YDBCloudOperationType_CreateDir] )
		{
			return cloudPath.path;
		}
	}
	
	return nil; // Don't attach
}

/**
 * Subclasses MUST override this method.
 *
 * The dependencyUUIDs must generated for each operation prior to handing it to the pipeline/graph.
 * This is typically done in [YapDatabaseCloudCoreTransaction processOperations:::].
**/
- (NSSet *)dependencyUUIDs
{
	return dependencyUUIDs;
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
		if (![dependency isKindOfClass:[NSUUID class]]  &&
		    ![dependency isKindOfClass:[NSString class]] )
		{
			YDBLogError(@"Invalid dependencies: Bad class: %@", [dependency class]);
			return NO;
		}
	}
	
	return YES;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Private API
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)clearDependencyUUIDs
{
	dependencyUUIDs = nil;
}

- (void)addDependencyUUID:(NSUUID *)uuid
{
	if (uuid == nil) return;
	
	if (dependencyUUIDs == nil)
	{
		dependencyUUIDs = [[NSSet alloc] initWithObjects:uuid, nil];
	}
	else if (![dependencyUUIDs containsObject:uuid])
	{
		NSMutableSet *newDependencyUUIDs = [dependencyUUIDs mutableCopy];
		[newDependencyUUIDs addObject:uuid];
		
		dependencyUUIDs = [newDependencyUUIDs copy];
	}
}

- (void)replaceDependencyUUID:(NSUUID *)oldUUID with:(NSUUID *)newUUID
{
	if ([dependencyUUIDs containsObject:oldUUID])
	{
		NSMutableSet *newDependencyUUIDs = [dependencyUUIDs mutableCopy];
		
		[newDependencyUUIDs removeObject:oldUUID];
		[newDependencyUUIDs addObject:newUUID];
		
		dependencyUUIDs = [newDependencyUUIDs copy];
	}
}

- (YDBCloudFileOpProcessResult)processEarlierOperationFromSameTransaction:(YapDatabaseCloudCoreFileOperation *)earlierOp
{
	// Example 1:
	//
	// earlier: upload /foo/bar/file.txt
	// later  : upload /foo/bar/file.txt  (should be merged)
	//
	// Example 2:
	//
	// earlier: createdir /foo/bar
	// later  : upload    /foo/bar/file.txt  (later depends on earlier)
	//
	// Example 3:
	//
	// earlier: delete    /foo/bar/
	// later  : createdir /foo/bar  (later depends on earlier)
	
	YapFilePath *earlier_src = earlierOp->cloudPath;
	YapFilePath *earlier_dst = earlierOp->targetCloudPath;
	
	YapFilePath *later_src = cloudPath;
	YapFilePath *later_dst = targetCloudPath;
	
	if ([earlier_src isEqualOrContainsFilePath:later_src])
	{
		if (self.isUploadOperation &&
		    earlierOp.isUploadOperation &&
		    [earlier_src isEqualToFilePath:later_src])
		{
			[self mergeEarlierOperationFromSameTransaction:earlierOp];
			return YDBCloudFileOpProcessResult_MergedIntoLater;
		}
		else
		{
			return YDBCloudFileOpProcessResult_DependentOnEarlier;
		}
	}
	
	if ([earlier_dst isEqualOrContainsFilePath:later_src])
	{
		return YDBCloudFileOpProcessResult_DependentOnEarlier;
	}
	
	if ([earlier_src isEqualOrContainsFilePath:later_dst])
	{
		return YDBCloudFileOpProcessResult_DependentOnEarlier;
	}
	
	if ([earlier_dst isEqualOrContainsFilePath:later_dst])
	{
		return YDBCloudFileOpProcessResult_DependentOnEarlier;
	}
	
	if (self.isCreateDirOperation)
	{
		if ([later_src containsFilePath:earlier_src])
		{
			return YDBCloudFileOpProcessResult_DependentOnLater;
		}
		
		if ([later_src containsFilePath:earlier_dst])
		{
			return YDBCloudFileOpProcessResult_DependentOnLater;
		}
	}
	
	return YDBCloudFileOpProcessResult_Continue;
}

/**
 * Invoked in order to merge an earlier upload operation (from the same transaction) with the same cloudPath.
**/
- (void)mergeEarlierOperationFromSameTransaction:(YapDatabaseCloudCoreFileOperation *)earlierOp
{
	// Subclasses may optionally override me
}

/**
 * Invoked for every operation from later transactions.
 * 
 * If the operation needs to be modified in any way, then a copy should be created, modified & returned.
**/
- (instancetype)updateWithOperationFromLaterTransaction:(YapDatabaseCloudCoreFileOperation *)newOperation
{
	// Subclasses may optionally override me
	return nil;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Equality
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)isEqualToOperation:(YapDatabaseCloudCoreOperation *)inOp
{
	if (![super isEqualToOperation:inOp]) return NO;
	
	if (![inOp isKindOfClass:[YapDatabaseCloudCoreFileOperation class]]) return NO;
	
	__unsafe_unretained YapDatabaseCloudCoreFileOperation *op = (YapDatabaseCloudCoreFileOperation *)inOp;
	
	if (!YDB_IsEqualOrBothNil(type, op->type)) return NO;
	if (!YDB_IsEqualOrBothNil(cloudPath, op->cloudPath)) return NO;
	if (!YDB_IsEqualOrBothNil(targetCloudPath, op->targetCloudPath)) return NO;
	if (!YDB_IsEqualOrBothNil(shouldAttach, op->shouldAttach)) return NO;
	if (!YDB_IsEqualOrBothNil(dependencyUUIDs, op->dependencyUUIDs)) return NO;
	
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
	NSMutableSet *properties = [super monitoredProperties];
	
	[properties addObject:NSStringFromSelector(@selector(cloudPath))];       // readwrite internally
	[properties addObject:NSStringFromSelector(@selector(targetCloudPath))]; // readwrite internally
	[properties addObject:NSStringFromSelector(@selector(shouldAttach))];
	
	return properties;
}

@end
