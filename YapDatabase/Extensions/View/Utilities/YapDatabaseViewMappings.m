#import "YapDatabaseViewMappingsPrivate.h"

#import "YapAbstractDatabaseConnection.h"
#import "YapAbstractDatabaseTransaction.h"

#import "YapDatabaseView.h"
#import "YapCollectionsDatabaseViewTransaction.h"

#import "YapDatabaseLogging.h"

#if ! __has_feature(objc_arc)
#warning This file must be compiled with ARC. Use -fobjc-arc flag (or convert project to ARC).
#endif

/**
 * Define log level for this file: OFF, ERROR, WARN, INFO, VERBOSE
 * See YapDatabaseLogging.h for more information.
**/
#if DEBUG
  static const int ydbLogLevel = YDB_LOG_LEVEL_WARN;
#else
  static const int ydbLogLevel = YDB_LOG_LEVEL_WARN;
#endif


@implementation YapDatabaseViewMappings
{
	// Immutable init parameters
	NSArray *allGroups;
	NSString *registeredViewName;
	
	// Mappings and cached counts
	NSMutableArray *visibleGroups;
	NSMutableDictionary *counts;
	
	// Configuration
	NSMutableSet *dynamicSections;
	NSMutableDictionary *rangeOptions;
	NSMutableDictionary *dependencies;
	NSMutableDictionary *reverse;
	
	// Snapshot (used for error detection)
	uint64_t snapshotOfLastUpdate;
}

@synthesize allGroups = allGroups;
@synthesize view = registeredViewName;

@synthesize snapshotOfLastUpdate = snapshotOfLastUpdate;

- (id)initWithGroups:(NSArray *)inGroups
                view:(NSString *)inRegisteredViewName
{
	if ((self = [super init]))
	{
		allGroups = [[NSArray alloc] initWithArray:inGroups copyItems:YES];
		registeredViewName = [inRegisteredViewName copy];
		
		id sharedKeySet = [NSDictionary sharedKeySetForKeys:allGroups];
		
		visibleGroups = [[NSMutableArray alloc] initWithCapacity:[allGroups count]];
		counts = [NSMutableDictionary dictionaryWithSharedKeySet:sharedKeySet];
		
		dynamicSections = [[NSMutableSet alloc] initWithCapacity:[allGroups count]];
		rangeOptions = [NSMutableDictionary dictionaryWithSharedKeySet:sharedKeySet];
		dependencies = [NSMutableDictionary dictionaryWithSharedKeySet:sharedKeySet];
		
		snapshotOfLastUpdate = UINT64_MAX;
	}
	return self;
}

- (id)copyWithZone:(NSZone *)zone
{
	YapDatabaseViewMappings *copy = [[YapDatabaseViewMappings alloc] init];
	copy->allGroups = allGroups;
	copy->registeredViewName = registeredViewName;
	
	copy->visibleGroups = [visibleGroups mutableCopy];
	copy->counts = [counts mutableCopy];
	
	copy->dynamicSections = [dynamicSections mutableCopy];
	copy->rangeOptions = [rangeOptions mutableCopy];
	copy->dependencies = [dependencies mutableCopy];
	copy->reverse = [reverse mutableCopy];
	
	copy->snapshotOfLastUpdate = snapshotOfLastUpdate;
	
	return copy;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Configuration
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)isDynamicSectionForAllGroups
{
	return ([dynamicSections count] == [allGroups count]);
}

- (void)setIsDynamicSectionForAllGroups:(BOOL)isDynamic
{
	if (isDynamic)
		[dynamicSections addObjectsFromArray:allGroups];
	else
		[dynamicSections removeAllObjects];
}

- (BOOL)isDynamicSectionForGroup:(NSString *)group
{
	return [dynamicSections containsObject:group];
}

- (void)setIsDynamicSection:(BOOL)isDynamic forGroup:(NSString *)group
{
	if (![allGroups containsObject:group]) {
		YDBLogWarn(@"%@ - mappings doesn't contain group(%@), only: %@", THIS_METHOD, group, allGroups);
		return;
	}
	
	[dynamicSections addObject:group];
}

- (void)setRangeOptions:(YapDatabaseViewRangeOptions *)rangeOpts forGroup:(NSString *)group
{
	if (rangeOpts == nil) {
		[self removeRangeOptionsForGroup:group];
		return;
	}
	
	if (![allGroups containsObject:group]) {
		YDBLogWarn(@"%@ - mappings doesn't contain group(%@), only: %@", THIS_METHOD, group, allGroups);
		return;
	}
	
	if (snapshotOfLastUpdate == UINT64_MAX)
	{
		// We don't have the counts yet, so we can't set rangeOpts.length yet.
		
		// Store private immutable copy
		rangeOpts = [rangeOpts copy];
		[rangeOptions setObject:rangeOpts forKey:group];
	}
	else
	{
		// Normal setter logic
		
		[self _setRangeOptions:rangeOpts forGroup:group];
		[self updateVisibilityForGroup:group];
	}
}

- (void)_setRangeOptions:(YapDatabaseViewRangeOptions *)rangeOpts forGroup:(NSString *)group
{
	// Set a valid rangeOpts.length using the known group count
	
	NSUInteger count = [[counts objectForKey:group] unsignedIntegerValue];
	
	NSUInteger desiredLength = rangeOpts.length;
	NSUInteger offset = rangeOpts.offset;
	
	NSUInteger maxLength = (offset >= count) ? 0 : count - offset;
	NSUInteger length = MIN(desiredLength, maxLength);
	
	// Store private immutable copy
	rangeOpts = [rangeOpts copyWithNewLength:length];
	[rangeOptions setObject:rangeOpts forKey:group];
}

- (YapDatabaseViewRangeOptions *)rangeOptionsForGroup:(NSString *)group
{
	// Return copy. Our internal version must remain immutable.
	return [[rangeOptions objectForKey:group] copy];
}

- (void)removeRangeOptionsForGroup:(NSString *)group
{
	[rangeOptions removeObjectForKey:group];
}

- (void)setCellDrawingDependencyForNeighboringCellWithOffset:(NSInteger)offset forGroup:(NSString *)group
{
	[self setCellDrawingDependencyOffsets:[NSSet setWithObject:@(offset)] forGroup:group];
}

- (void)setCellDrawingDependencyOffsets:(NSSet *)offsets forGroup:(NSString *)group
{
	if (![allGroups containsObject:group]) {
		YDBLogWarn(@"%@ - mappings doesn't contain group(%@), only: %@", THIS_METHOD, group, allGroups);
		return;
	}

	NSMutableSet *validOffsets = [NSMutableSet setWithCapacity:[offsets count]];

	for (id obj in offsets)
	{
		if ([obj isKindOfClass:[NSNumber class]])
		{
			if ([obj integerValue] != 0)
			{
				[validOffsets addObject:obj];
			}
		}
	}

	[dependencies setObject:[validOffsets copy] forKey:group];
}

- (NSSet *)cellDrawingDependencyOffsetsForGroup:(NSString *)group
{
	return [dependencies objectForKey:group];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Initialization & Updates
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)updateWithTransaction:(YapAbstractDatabaseTransaction *)transaction
{
	for (NSString *group in allGroups)
	{
		NSUInteger count = [[transaction ext:registeredViewName] numberOfKeysInGroup:group];
		
		[counts setObject:@(count) forKey:group];
	}
	
	BOOL firstUpdate = (snapshotOfLastUpdate == UINT64_MAX);
	snapshotOfLastUpdate = transaction.abstractConnection.snapshot;
	
	if (firstUpdate)
		[self initializeRangeOptsLength];
	
	[self updateVisibility];
}

/**
 * This method is internal.
 * It is only for use by the unit tests in TestViewChangeLogic.
**/
- (void)updateWithCounts:(NSDictionary *)newCounts
{
	for (NSString *group in allGroups)
	{
		NSUInteger count = [[newCounts objectForKey:group] unsignedIntegerValue];
		
		[counts setObject:@(count) forKey:group];
	}
	
	BOOL firstUpdate = (snapshotOfLastUpdate == UINT64_MAX);
	snapshotOfLastUpdate = 0;
	
	if (firstUpdate)
		[self initializeRangeOptsLength];
	
	[self updateVisibility];
}

- (void)initializeRangeOptsLength
{
	NSAssert(snapshotOfLastUpdate != UINT64_MAX, @"The counts are needed to set rangeOpts.length");
	
	for (NSString *group in [rangeOptions allKeys])
	{
		YapDatabaseViewRangeOptions *rangeOpts = [rangeOptions objectForKey:group];
		
		// Go through the internal setter again so all the logic is in the same place.
		[self _setRangeOptions:rangeOpts forGroup:group];
	}
}

- (void)updateVisibility
{
	[visibleGroups removeAllObjects];
	
	for (NSString *group in allGroups)
	{
		NSUInteger count;
		
		YapDatabaseViewRangeOptions *rangeOpts = [rangeOptions objectForKey:group];
		if (rangeOpts)
			count = rangeOpts.length;
		else
			count = [[counts objectForKey:group] unsignedIntegerValue];
		
		if (count > 0 || ![dynamicSections containsObject:group])
			[visibleGroups addObject:group];
	}
}

- (void)updateVisibilityForGroup:(NSString *)group
{
	NSUInteger count;
	
	YapDatabaseViewRangeOptions *rangeOpts = [rangeOptions objectForKey:group];
	if (rangeOpts)
		count = rangeOpts.length;
	else
		count = [[counts objectForKey:group] unsignedIntegerValue];
	
	if (count > 0 || ![dynamicSections containsObject:group])
		[visibleGroups addObject:group];
	else
		[visibleGroups removeObject:group];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Internal
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSMutableDictionary *)counts
{
	return [counts mutableCopy];
}

- (NSUInteger)fullCountForGroup:(NSString *)group
{
	return [[counts objectForKey:group] unsignedIntegerValue];
}

- (NSUInteger)visibleCountForGroup:(NSString *)group
{
	return [self numberOfItemsInGroup:group];
}

- (NSDictionary *)rangeOptions
{
	return [rangeOptions copy];
}

- (NSDictionary *)dependencies
{
	return [dependencies copy];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Mappings
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSUInteger)numberOfSections
{
	return [visibleGroups count];
}

- (NSUInteger)numberOfItemsInSection:(NSUInteger)section
{
	return [self numberOfItemsInGroup:[self groupForSection:section]];
}

- (NSUInteger)numberOfItemsInGroup:(NSString *)group
{
	if (group == nil) return 0;
	if (snapshotOfLastUpdate == UINT64_MAX) return 0;
	
	YapDatabaseViewRangeOptions *rangeOpts = [rangeOptions objectForKey:group];
	if (rangeOpts)
	{
		return rangeOpts.length;
	}
	else
	{
		return [[counts objectForKey:group] unsignedIntegerValue];
	}
}

- (NSString *)groupForSection:(NSUInteger)section
{
	if (section < [visibleGroups count])
		return [visibleGroups objectAtIndex:section];
	else
		return nil;
}

- (NSUInteger)sectionForGroup:(NSString *)group
{
	NSUInteger section = 0;
	for (NSString *visibleGroup in visibleGroups)
	{
		if ([visibleGroup isEqualToString:group])
		{
			return section;
		}
		section++;
	}
	
	return NSNotFound;
}

- (NSArray *)visibleGroups
{
	return [visibleGroups copy];
}

- (BOOL)getGroup:(NSString **)groupPtr index:(NSUInteger *)indexPtr forIndexPath:(NSIndexPath *)indexPath
{
  #if TARGET_OS_IPHONE
	NSUInteger section = indexPath.section;
	NSUInteger row = indexPath.row;
  #else
	NSUInteger section = [indexPath indexAtPosition:0];
	NSUInteger row = [indexPath indexAtPosition:1];
  #endif
	
	NSString *group = [self groupForSection:section];
	if (group == nil)
	{
		if (groupPtr) *groupPtr = nil;
		if (indexPtr) *indexPtr = NSNotFound;
		
		return NO;
	}
	
	NSUInteger index = [self groupIndexForRow:row inGroup:group];
	
	if (groupPtr) *groupPtr = group;
	if (indexPtr) *indexPtr = index;
	
	return (index != NSNotFound);
}

- (NSUInteger)groupIndexForRow:(NSUInteger)row inSection:(NSUInteger)section
{
	return [self groupIndexForRow:row inGroup:[self groupForSection:section]];
}

- (NSUInteger)groupIndexForRow:(NSUInteger)row inGroup:(NSString *)group
{
	if (group == nil) return NSNotFound;
	
	YapDatabaseViewRangeOptions *rangeOpts = [rangeOptions objectForKey:group];
	if (rangeOpts)
	{
		if (rangeOpts.pin == YapDatabaseViewBeginning)
		{
			// Offset is from beginning (index zero)
			
			return (rangeOpts.offset + row);
		}
		else // if (rangeOpts.pin == YapDatabaseViewEnd)
		{
			// Offset is from end (index last)
			
			NSUInteger count = [self numberOfItemsInGroup:group];
			NSUInteger reverseOffset = rangeOpts.offset + rangeOpts.length;
			
			if (reverseOffset <= count)
			{
				return ((count - reverseOffset) + row);
			}
			else
			{
				return NSNotFound;
			}
		}
	}
	else
	{
		return row;
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Logging
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)description
{
	NSMutableString *description = [NSMutableString string];
	[description appendFormat:@"<YapDatabaseViewMappings[%p]: view(%@)\n", self, registeredViewName];
	
	NSUInteger i = 0;
	NSString *visibleGroup = ([visibleGroups count] > 0) ? [visibleGroups objectAtIndex:0] : nil;
	
	for (NSString *group in allGroups)
	{
		if ([group isEqualToString:visibleGroup])
		{
			[description appendFormat:@"  section(%lu) count(%@) group(%@)\n",
			                              (unsigned long)i, [counts objectForKey:group], group];
			
			i++;
			visibleGroup = ([visibleGroups count] > i) ? [visibleGroups objectAtIndex:i] : nil;
		}
		else
		{
			[description appendFormat:@"  section(-) count(%@) group(%@)\n",
			                              [counts objectForKey:group], group];
		}
	}
	
	[description appendString:@">"];
	
	return description;
}

@end
