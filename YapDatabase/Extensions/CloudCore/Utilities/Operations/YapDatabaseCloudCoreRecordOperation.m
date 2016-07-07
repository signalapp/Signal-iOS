/**
 * Copyright Deusty LLC.
**/

#import "YapDatabaseCloudCoreRecordOperation.h"
#import "YapDatabaseCloudCoreOperationPrivate.h"
#import "YapDatabaseCloudCore.h"

static int const kYapDatabaseCloudCoreRecordOperation_CurrentVersion = 0;
#pragma unused(kYapDatabaseCloudCoreRecordOperation_CurrentVersion)

static NSString *const k_version        = @"version_record"; // subclasses should use version_XXX
static NSString *const k_originalValues = @"originalValues";
static NSString *const k_updatedValues  = @"updatedValues";
static NSString *const k_updatedKeys    = @"updatedKeys";


@implementation YapDatabaseCloudCoreRecordOperation

@synthesize originalValues = originalValues;
@synthesize updatedValues = updatedValues;
@synthesize restoreInfo_changedKeys = restoreInfo_changedKeys;
@synthesize needsStoreFullUpdatedValues = needsStoreFullUpdatedValues;

+ (YapDatabaseCloudCoreRecordOperation *)uploadWithCloudPath:(YapFilePath *)cloudPath
{
	return [[YapDatabaseCloudCoreRecordOperation alloc] initWithType:YDBCloudOperationType_Upload
	                                                       cloudPath:cloudPath
	                                                 targetCloudPath:nil];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSCoding
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)encodeWithCoder:(NSCoder *)coder
{
	[super encodeWithCoder:coder];
	
	if (kYapDatabaseCloudCoreRecordOperation_CurrentVersion != 0) {
		[coder encodeInt:kYapDatabaseCloudCoreRecordOperation_CurrentVersion forKey:k_version];
	}
	
	[coder encodeObject:originalValues forKey:k_originalValues];
	
	if (needsStoreFullUpdatedValues) {
		[coder encodeObject:updatedValues forKey:k_updatedValues];
	}
	else {
		[coder encodeObject:[updatedValues allKeys] forKey:k_updatedKeys];
	}
}

- (instancetype)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super initWithCoder:decoder]))
	{
		originalValues = [decoder decodeObjectForKey:k_originalValues];
		
		updatedValues = [decoder decodeObjectForKey:k_updatedValues];
		if (updatedValues) {
			needsStoreFullUpdatedValues = YES;
		}
		else {
			restoreInfo_changedKeys = [decoder decodeObjectForKey:k_updatedKeys];
		}
	}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSCopying
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (instancetype)copyWithZone:(NSZone *)zone
{
	YapDatabaseCloudCoreRecordOperation *copy = [super copyWithZone:zone];
	
	copy->originalValues = originalValues;
	copy->updatedValues = updatedValues;
	copy->restoreInfo_changedKeys = restoreInfo_changedKeys;
	copy->needsStoreFullUpdatedValues = needsStoreFullUpdatedValues;
	
	return copy;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Merge Logic
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Invoked in order to merge an earlier upload operation (from the same transaction) with the same cloudPath.
**/
- (void)mergeEarlierOperationFromSameTransaction:(YapDatabaseCloudCoreFileOperation *)earlierOperation
{
	if ([earlierOperation isKindOfClass:[YapDatabaseCloudCoreRecordOperation class]])
	{
		__unsafe_unretained YapDatabaseCloudCoreRecordOperation *earlierRecordOperation =
		                   (YapDatabaseCloudCoreRecordOperation *)earlierOperation;
			
		[self mergeEarlierRecordOperationFromSameTransaction:earlierRecordOperation];
	}
	
	[super mergeEarlierOperationFromSameTransaction:earlierOperation];
}

/**
 * Utility method that handles the actual merge with the other record operation.
 * Invoked from mergeEarlierOperationFromSameTransaction.
**/
- (void)mergeEarlierRecordOperationFromSameTransaction:(YapDatabaseCloudCoreRecordOperation *)earlierOperation
{
	NSAssert(self.isImported, @"Unexpected operation state");
	NSAssert(self.isImmutable, @"Unexpected operation state");
	
	// originalValues:
	// The oldOperation.originalValues is added to our own originalValues, and OVERRIDES our values
	
	NSMutableDictionary *new_originalValues = [originalValues mutableCopy];
	
	[new_originalValues addEntriesFromDictionary:earlierOperation.originalValues];
	
	// updatedValues:
	// The oldOperation.updatedValues is added to our own updatedValues, but does NOT override our values
	
	NSMutableDictionary *new_updatedValues = [updatedValues mutableCopy];
	
	[earlierOperation.updatedValues enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
	
		if ([new_updatedValues objectForKey:key] == nil)
		{
			[new_updatedValues setObject:obj forKey:key];
		}
	}];
	
	// Set new ivars (do NOT go through setter)
	
	originalValues = [new_originalValues copy];
	updatedValues = [new_updatedValues copy];
}

/**
 * Invoked for every operation from later transactions.
 *
 * If the operation needs to be modified in any way, then a copy should be created, modified & returned.
**/
- (instancetype)updateWithOperationFromLaterTransaction:(YapDatabaseCloudCoreFileOperation *)newOperation
{
	NSAssert(self.isImported, @"Unexpected operation state");
	NSAssert(self.isImmutable, @"Unexpected operation state");
	
	YapDatabaseCloudCoreRecordOperation *modifiedCopy = nil;
	
	if ([newOperation isKindOfClass:[YapDatabaseCloudCoreRecordOperation class]])
	{
		__unsafe_unretained YapDatabaseCloudCoreRecordOperation *newRecordOperation =
		                   (YapDatabaseCloudCoreRecordOperation *)newOperation;
		
		BOOL cloudPathMatches = [self.cloudPath isEqualToFilePath:newRecordOperation.cloudPath];
		if (cloudPathMatches)
		{
			modifiedCopy = [self updateWithRecordOperationFromLaterTransaction:newRecordOperation];
		}
	}
	
	return modifiedCopy;
}

/**
 * Utility method that handles the actual merge with the other record operation.
 * Invoked from updateWithOperationFromLaterTransaction.
**/
- (instancetype)updateWithRecordOperationFromLaterTransaction:(YapDatabaseCloudCoreRecordOperation *)newOperation
{
	__block YapDatabaseCloudCoreRecordOperation *modifiedCopy = nil;
	__block NSMutableDictionary *newOriginalValues = nil;
	
	[newOperation.updatedValues enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
		
		if ([updatedValues objectForKey:key])
		{
			// A value that we modified was modified again.
			// Make sure we store the version that we have in the database.
			
			if (!self.needsStoreFullUpdatedValues)
			{
				if (modifiedCopy == nil)
					modifiedCopy = [self copy];
				
				modifiedCopy.needsStoreFullUpdatedValues = YES;
			}
		}
		else if (![originalValues objectForKey:key])
		{
			// A value that we did NOT modify has been modified.
			// Copy the original value into our set of original values.
			
			id originalValue = [newOperation.originalValues objectForKey:key];
			if (originalValue)
			{
				// Copy the original value into our set of original values.
				
				if (newOriginalValues == nil)
					newOriginalValues = [originalValues mutableCopy];
				
				[newOriginalValues setObject:originalValue forKey:key];
			}
		}
	}];
	
	if (newOriginalValues)
	{
		if (modifiedCopy == nil)
			modifiedCopy = [self copy];
		
		modifiedCopy.originalValues = [newOriginalValues copy];
	}
	
	return modifiedCopy;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Equality
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)isEqualToOperation:(YapDatabaseCloudCoreOperation *)inOp
{
	if (![super isEqualToOperation:inOp]) return NO;
	
	if (![inOp isKindOfClass:[YapDatabaseCloudCoreRecordOperation class]]) return NO;
	
	__unsafe_unretained YapDatabaseCloudCoreRecordOperation *op = (YapDatabaseCloudCoreRecordOperation *)inOp;
	
	if (!YDB_IsEqualOrBothNil(originalValues, op->originalValues)) return NO;
	if (!YDB_IsEqualOrBothNil(updatedValues, op->updatedValues)) return NO;
	if (!YDB_IsEqualOrBothNil(restoreInfo_changedKeys, op->restoreInfo_changedKeys)) return NO;
	
	if (needsStoreFullUpdatedValues != op->needsStoreFullUpdatedValues) return NO;
	
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
	
	[properties addObject:NSStringFromSelector(@selector(originalValues))];
	[properties addObject:NSStringFromSelector(@selector(updatedValues))];
	[properties addObject:NSStringFromSelector(@selector(needsStoreFullUpdatedValues))];
	
	return properties;
}

@end
