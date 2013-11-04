#import "YapDatabaseViewMappingsPrivate.h"
#import "YapDatabaseViewRangeOptionsPrivate.h"

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
	NSMutableSet *reverse;
	NSMutableDictionary *rangeOptions;
	NSMutableDictionary *dependencies;
	
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
		
		NSUInteger allGroupsCount = [allGroups count];
		
		visibleGroups = [[NSMutableArray alloc] initWithCapacity:allGroupsCount];
		
		dynamicSections = [[NSMutableSet alloc] initWithCapacity:allGroupsCount];
		reverse         = [[NSMutableSet alloc] initWithCapacity:allGroupsCount];
		
		id sharedKeySet = [NSDictionary sharedKeySetForKeys:allGroups];
		
		counts       = [NSMutableDictionary dictionaryWithSharedKeySet:sharedKeySet];
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
	copy->reverse = [reverse mutableCopy];
	copy->rangeOptions = [rangeOptions mutableCopy];
	copy->dependencies = [dependencies mutableCopy];
	
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
	
	if (isDynamic)
		[dynamicSections addObject:group];
	else
		[dynamicSections removeObject:group];
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
	
	// Store private immutable copy
	if ([reverse containsObject:group])
		rangeOpts = [rangeOpts copyAndReverse];
	else
		rangeOpts = [rangeOpts copy];
	
	if (snapshotOfLastUpdate == UINT64_MAX)
	{
		// We don't have the counts yet, so we can't set rangeOpts.length yet.
		
		[rangeOptions setObject:rangeOpts forKey:group];
	}
	else
	{
		// Normal setter logic
		
		[self updateRangeOptions:rangeOpts forGroup:group];
		[self updateVisibilityForGroup:group];
	}
}

- (YapDatabaseViewRangeOptions *)rangeOptionsForGroup:(NSString *)group
{
	YapDatabaseViewRangeOptions *rangeOpts = [rangeOptions objectForKey:group];
	
	// Return copy. Our internal version must remain immutable.
	
	if ([reverse containsObject:group])
		return [rangeOpts copyAndReverse];
	else
		return [rangeOpts copy];
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
	BOOL needsReverse = [reverse containsObject:group];
	
	for (id obj in offsets)
	{
		if ([obj isKindOfClass:[NSNumber class]])
		{
			NSInteger offset = [obj integerValue];
			if (offset != 0)
			{
				if (needsReverse)
					[validOffsets addObject:@(offset * -1)];
				else
					[validOffsets addObject:obj];
			}
		}
		else
		{
			YDBLogWarn(@"%@ - Non-NSNumber passed in offsets: %@", THIS_METHOD, obj);
		}
	}

	[dependencies setObject:[validOffsets copy] forKey:group];
}

- (NSSet *)cellDrawingDependencyOffsetsForGroup:(NSString *)group
{
	NSSet *offsets = [dependencies objectForKey:group];
	
	if ([reverse containsObject:group])
	{
		NSMutableSet *reverseOffsets = [NSMutableSet setWithCapacity:[offsets count]];
		for (NSNumber *obj in offsets)
		{
			NSUInteger offset = [obj integerValue];
			[reverseOffsets addObject:@(offset * -1)];
		}
		
		return [reverseOffsets copy];
	}
	else
	{
		return offsets;
	}
}

- (BOOL)isReversedForGroup:(NSString *)group
{
	return [reverse containsObject:group];
}

- (void)setIsReversed:(BOOL)isReversed forGroup:(NSString *)group
{
	if (![allGroups containsObject:group]) {
		YDBLogWarn(@"%@ - mappings doesn't contain group(%@), only: %@", THIS_METHOD, group, allGroups);
		return;
	}
	
	if (isReversed)
		[reverse addObject:group];
	else
		[reverse removeObject:group];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Initialization & Updates
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)updateWithTransaction:(YapAbstractDatabaseTransaction *)transaction
{
	if (transaction.abstractConnection.isInLongLivedReadTransaction == NO)
	{
		NSString *reason = @"YapDatabaseViewMappings requires the connection to be in a longLivedReadTransaction.";
		
		NSString *failureReason =
		    @"The architecture surrounding mappings is designed to move from one longLivedReadTransaction to another."
			@" This allows you to freeze the data-source (databaseConnection) of your UI on a particular commit."
			@" And then atomically move the data-source from an older commit to a newer commit in response to"
			@" YapDatabaseModifiedNotifications. This ensures that the data-source for your UI remains in a steady"
			@" state at all times, and that updates are properly handled using the appropriate update mechanisms"
			@" (and properly animated if desired)."
			@" For example code, please see the wiki: https://github.com/yaptv/YapDatabase/wiki/Views";
			
		NSString *suggestion =
		    @"You must invoke [databaseConnection beginLongLivedReadTransaction] before you initialize the mappings";
		
		NSDictionary *userInfo = @{
			NSLocalizedFailureReasonErrorKey: failureReason,
			NSLocalizedRecoverySuggestionErrorKey: suggestion };
		
		// Here's what you SHOULD be doing: (correct)
		//
		// [databaseConnection beginLongLivedReadConnection];
		// [databaseConnection readWithBlock:^(YapDatabaseConnectionReadTransaction *transaction){
		//     [mappings updateWithTransaction:transaction];
		// }];
		//
		// Here's what you ARE doing: (wrong)
		//
		// [databaseConnection readWithBlock:^(YapDatabaseConnectionReadTransaction *transaction){
		//     [mappings updateWithTransaction:transaction];
		// }];
		// [databaseConnection beginLongLivedReadConnection];
		//
		//
		// Warning: Do NOT, under any circumstance, comment out this exception.
		
		@throw [NSException exceptionWithName:@"YapDatabaseException" reason:reason userInfo:userInfo];
	}
	
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
		[self updateRangeOptions:rangeOpts forGroup:group];
	}
}

- (void)updateRangeOptions:(YapDatabaseViewRangeOptions *)rangeOpts forGroup:(NSString *)group
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

/**
 * This method is used by YapDatabaseViewChange.
 *
 * After processing changeset(s), the length and/or offset may change.
 * The new length and/or offsets are properly calculated,
 * and then this method is used to avoid duplicating the calculations.
**/
- (void)updateRangeOptionsForGroup:(NSString *)group withNewLength:(NSUInteger)newLength newOffset:(NSUInteger)newOffset
{
	YapDatabaseViewRangeOptions *rangeOpts = [rangeOptions objectForKey:group];
	rangeOpts = [rangeOpts copyWithNewLength:newLength newOffset:newOffset];
	
	[rangeOptions setObject:rangeOpts forKey:group];
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

- (NSSet *)reverse
{
	return [reverse copy];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Getters
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Returns the actual number of visible sections.
 * 
 * This number may be less than the original count of groups passed in the init method.
 * That is, if dynamic sections are enabled for one or more groups, and some of these groups have zero items,
 * then those groups will be removed from the visible list of groups. And thus the section count may be less.
**/
- (NSUInteger)numberOfSections
{
	return [visibleGroups count];
}

/**
 * Returns the number of items in the given section.
 * @see groupForSection
**/
- (NSUInteger)numberOfItemsInSection:(NSUInteger)section
{
	return [self numberOfItemsInGroup:[self groupForSection:section]];
}

/**
 * Returns the number of items in the given group.
 *
 * This is the cached value from the last time one of the following methods was invoked:
 * - updateWithTransaction:
 * - changesForNotifications:withMappings:
**/
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

/**
 * The visibleGroups property returns the current sections setup.
 * That is, it only contains the visible groups that are being represented as sections in the view.
 *
 * If all sections are static, then visibleGroups will always be the same as allGroups.
 * However, if one or more sections are dynamic, then the visible groups may be a subset of allGroups.
 *
 * Dynamic groups/sections automatically "disappear" if/when they become empty.
**/
- (NSArray *)visibleGroups
{
	return [visibleGroups copy];
}

/**
 * Returns YES if there are zero items in all sections/groups.
**/
- (BOOL)isEmpty
{
	if (snapshotOfLastUpdate == UINT64_MAX) return YES;
	
	for (NSString *group in visibleGroups)
	{
		YapDatabaseViewRangeOptions *rangeOpts = [rangeOptions objectForKey:group];
		if (rangeOpts)
		{
			if (rangeOpts.length > 0)
				return NO;
		}
		else
		{
			if ([[counts objectForKey:group] unsignedIntegerValue] > 0)
				return NO;
		}
	}
	
	return YES;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Mapping UI -> View
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Maps from a section (in the UI) to a group (in the View).
 *
 * Returns the group for the given section.
 * This method properly takes into account dynamic groups.
 *
 * If the section is out-of-bounds, returns nil.
**/
- (NSString *)groupForSection:(NSUInteger)section
{
	if (section < [visibleGroups count])
		return [visibleGroups objectAtIndex:section];
	else
		return nil;
}

/**
 * Maps from an indexPath (in the UI) to a group & index (within the View).
 *
 * When using rangeOptions, the rows in your tableView/collectionView may not
 * directly match the index in the corresponding view & group.
 * 
 * For example, say a view has a group named "elders" and contains 100 items.
 * A fixed range is used to display only the last 20 items in the "elders" group (the 20 oldest elders).
 * Thus row zero in the tableView is actually index 80 in the "elders" group.
 * 
 * This method maps from an indexPath in the UI to the corresponding indexes and groups in the view.
 * 
 * That is, you pass in an indexPath or row & section from the UI perspective,
 * and it spits out the corresponding index within the view's group.
 * 
 * For example:
 * 
 * - (UITableViewCell *)tableView:(UITableView *)sender cellForRowAtIndexPath:(NSIndexPath *)indexPath
 * {
 *     NSString *group = nil;
 *     NSUInteger groupIndex = 0;
 *
 *     [mappings getGroup:&group index:&groupIndex forIndexPath:indexPath];
 *
 *     __block Elder *elder = nil;
 *     [databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
 *
 *         elder = [[transaction extension:@"elders"] objectAtIndex:groupIndex inGroup:group];
 *     }];
 *     
 *     // configure and return cell...
 * }
**/
- (BOOL)getGroup:(NSString **)groupPtr index:(NSUInteger *)indexPtr forIndexPath:(NSIndexPath *)indexPath
{
	if (indexPath == nil)
	{
		if (groupPtr) *groupPtr = nil;
		if (indexPtr) *indexPtr = NSNotFound;
		
		return NO;
	}
	
  #if TARGET_OS_IPHONE
	NSUInteger section = indexPath.section;
	NSUInteger row = indexPath.row;
  #else
	NSUInteger section = [indexPath indexAtPosition:0];
	NSUInteger row = [indexPath indexAtPosition:1];
  #endif
	
	return [self getGroup:groupPtr index:indexPtr forRow:row inSection:section];
}

/**
 * Maps from an indexPath (in the UI) to a group & index (within the View).
 *
 * When your UI doesn't exactly match up with the View in the database, this method does all the math for you.
 *
 * For example, if using rangeOptions, the rows in your tableView/collectionView may not
 * directly match the index in the corresponding view & group (in the database).
 * 
 * For example, say a view in the database has a group named "elders" and contains 100 items.
 * A fixed range is used to display only the last 20 items in the "elders" group (the 20 oldest elders).
 * Thus row zero in the tableView is actually index 80 in the "elders" group.
 *
 * So you pass in an indexPath or row & section from the UI perspective,
 * and it spits out the corresponding index within the database view's group.
 * 
 * Code sample:
 * 
 * - (UITableViewCell *)tableView:(UITableView *)sender cellForRowAtIndexPath:(NSIndexPath *)indexPath
 * {
 *     NSString *group = nil;
 *     NSUInteger groupIndex = 0;
 *
 *     [mappings getGroup:&group index:&groupIndex forIndexPath:indexPath];
 *
 *     __block Elder *elder = nil;
 *     [databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
 *
 *         elder = [[transaction extension:@"elders"] objectAtIndex:groupIndex inGroup:group];
 *     }];
 *     
 *     // configure and return cell...
 * }
**/
- (BOOL)getGroup:(NSString **)groupPtr
           index:(NSUInteger *)indexPtr
          forRow:(NSUInteger)row
       inSection:(NSUInteger)section
{
	NSString *group = [self groupForSection:section];
	if (group == nil)
	{
		if (groupPtr) *groupPtr = nil;
		if (indexPtr) *indexPtr = NSNotFound;
		
		return NO;
	}
	
	NSUInteger index = [self indexForRow:row inGroup:group];
	
	if (groupPtr) *groupPtr = group;
	if (indexPtr) *indexPtr = index;
	
	return (index != NSNotFound);
}

/**
 * Maps from a row & section (in the UI) to an index (within the View).
 * 
 * This method is shorthand for getGroup:index:forIndexPath: when you already know the group.
 * @see getGroup:index:forIndexPath:
**/
- (NSUInteger)indexForRow:(NSUInteger)row inSection:(NSUInteger)section
{
	return [self indexForRow:row inGroup:[self groupForSection:section]];
}

/**
 * Maps from a row & section (in the UI) to an index (within the View).
 * 
 * This method is shorthand for getGroup:index:forIndexPath: when you already know the group.
 * @see getGroup:index:forIndexPath:
**/
- (NSUInteger)indexForRow:(NSUInteger)row inGroup:(NSString *)group
{
	if (group == nil) return NSNotFound;
	
	NSUInteger visibleCount = [self visibleCountForGroup:group];
	if (row >= visibleCount)
		return NSNotFound;
	
	BOOL needsReverse = [reverse containsObject:group];
	
	YapDatabaseViewRangeOptions *rangeOpts = [rangeOptions objectForKey:group];
	if (rangeOpts)
	{
		if (rangeOpts.pin == YapDatabaseViewBeginning)
		{
			// rangeOpts.offset is from beginning (index zero)
			
			if (needsReverse)
			{
				NSUInteger upperBound = rangeOpts.offset + rangeOpts.length - 1;
				return upperBound - row;
			}
			else
			{
				return rangeOpts.offset + row;
			}
		}
		else // if (rangeOpts.pin == YapDatabaseViewEnd)
		{
			// rangeOpts.offset is from end (index last)
			
			NSUInteger fullCount = [self fullCountForGroup:group];
			
			if (needsReverse)
			{
				NSUInteger upperBound = fullCount - rangeOpts.offset - 1;
				return upperBound - row;
			}
			else
			{
				NSUInteger lowerBound = fullCount - rangeOpts.offset - rangeOpts.length;
				return lowerBound + row;
			}
		}
	}
	else
	{
		if (needsReverse)
		{
			NSUInteger fullCount = [self fullCountForGroup:group];
			return fullCount - row - 1;
		}
		else
		{
			return row;
		}
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Mapping View -> UI
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Maps from a group (in the View) to the corresponding section (in the UI).
 *
 * Returns the visible section number for the visible group.
 * If the group is NOT visible, returns NSNotFound.
 * If the group is NOT valid, returns NSNotFound.
 **/
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

/**
 * Maps from an index & group (in the View) to the corresponding row & section (in the UI).
 * 
 * Returns YES if the proper row & section were found.
 * Returns NO if the given index is NOT visible (or out-of-bounds).
 * Returns NO if the given group is NOT visible (or invalid).
**/
- (BOOL)getRow:(NSUInteger *)rowPtr
       section:(NSUInteger *)sectionPtr
      forIndex:(NSUInteger)index
       inGroup:(NSString *)group
{
	NSUInteger section = [self sectionForGroup:group];
	if (section == NSNotFound)
	{
		if (rowPtr) *rowPtr = 0;
		if (sectionPtr) *sectionPtr = 0;
		
		return NO;
	}
	
	NSUInteger row = [self rowForIndex:index inGroup:group];
	if (row == NSNotFound)
	{
		if (rowPtr) *rowPtr = 0;
		if (sectionPtr) *sectionPtr = 0;
		
		return NO;
	}
	
	if (rowPtr) *rowPtr = row;
	if (sectionPtr) *sectionPtr = section;
	
	return YES;
}

/**
 * Maps from an index & group (in the View) to the corresponding indexPath (in the UI).
 * 
 * Returns the indexPath with the proper section and row.
 * Returns nil if the group is NOT visible (or invalid).
 * Returns nil if the index is NOT visible (or out-of-bounds).
**/
- (NSIndexPath *)indexPathForIndex:(NSUInteger)index inGroup:(NSString *)group
{
	NSUInteger row = 0;
	NSUInteger section = 0;
	
	if ([self getRow:&row section:&section forIndex:index inGroup:group])
	{
	  #if TARGET_OS_IPHONE
		return [NSIndexPath indexPathForRow:row inSection:section];
	  #else
		NSUInteger indexes[] = {section, row};
		return [NSIndexPath indexPathWithIndexes:indexes length:2];
	  #endif
	}
	else
	{
		return nil;
	}
}

/**
 * Maps from an index & group (in the View) to the corresponding row (in the UI).
 * 
 * This method is shorthand for getRow:section:forIndex:inGroup: when you already know the section.
 * @see getRow:section:forIndex:inGroup:
**/
- (NSUInteger)rowForIndex:(NSUInteger)index inGroup:(NSString *)group
{
	if (group == nil) return NSNotFound;
	
	NSUInteger fullCount = [self fullCountForGroup:group];
	if (index >= fullCount)
		return NSNotFound;
	
	BOOL needsReverse = [reverse containsObject:group];
	
	YapDatabaseViewRangeOptions *rangeOpts = [rangeOptions objectForKey:group];
	if (rangeOpts)
	{
		if (rangeOpts.pin == YapDatabaseViewBeginning)
		{
			// rangeOpts.offset is from beginning (index zero)
			
			if (index < rangeOpts.offset)
				return NSNotFound;
			
			NSUInteger row = index - rangeOpts.offset;
			
			NSUInteger visibleCount = [self visibleCountForGroup:group];
			if (row >= visibleCount)
				return NSNotFound;
			
			if (needsReverse)
				return visibleCount - row - 1;
			else
				return row;
		}
		else // if (rangeOpts.pin == YapDatabaseViewEnd)
		{
			// rangeOpts.offset is from end (index last)
			
			NSUInteger visibleCount = [self visibleCountForGroup:group];
			
			NSUInteger upperBound = fullCount - rangeOpts.offset - 1;
			if (index > upperBound)
				return NSNotFound;
			
			NSUInteger lowerBound = upperBound - visibleCount + 1;
			if (index < lowerBound)
				return NSNotFound;
			
			if (needsReverse)
				return upperBound - index;
			else
				return index - lowerBound;
		}
	}
	else
	{
		if (needsReverse)
			return fullCount - index - 1; // we know fullCount > 0
		else
			return index;
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Getters + RangeOptions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * The YapDatabaseViewRangePosition struct represents the range window within the full group.
 * For example:
 *
 * You have a section in your tableView which represents a group that contains 100 items.
 * However, you've setup rangeOptions to only display the first 20 items:
 * 
 * YapDatabaseViewRangeOptions *rangeOptions =
 *     [YapDatabaseViewRangeOptions fixedRangeWithLength:20 offset:0 from:YapDatabaseViewBeginning];
 * [mappings setRangeOptions:rangeOptions forGroup:@"sales"];
 *
 * The corresponding rangePosition would be: (YapDatabaseViewRangePosition){
 *     .offsetFromBeginning = 0,
 *     .offsetFromEnd = 80,
 *     .length = 20
 * }
**/
- (YapDatabaseViewRangePosition)rangePositionForGroup:(NSString *)group;
{
	if (group == nil)
	{
		return (YapDatabaseViewRangePosition){
			.offsetFromBeginning = 0,
			.offsetFromEnd = 0,
			.length = 0
		};
	}
	
	NSUInteger groupCount = [[counts objectForKey:group] unsignedIntegerValue];
	
	YapDatabaseViewRangeOptions *rangeOpts = [rangeOptions objectForKey:group];
	YapDatabaseViewRangePosition rangePosition;
	
	if (rangeOpts)
	{
		NSUInteger rangeOffset = rangeOpts.offset;
		NSUInteger rangeLength = rangeOpts.length;
		
		if (rangeOpts.pin == YapDatabaseViewBeginning)
		{
			// Offset is from beginning (index zero)
			
			NSUInteger reverseOffset = rangeOffset + rangeLength;
			
			if (reverseOffset <= groupCount)
			{
				// Valid range
				
				rangePosition = (YapDatabaseViewRangePosition){
					.offsetFromBeginning = rangeOffset,
					.offsetFromEnd = groupCount - reverseOffset,
					.length = rangeLength
				};
			}
			else
			{
				// Range fell off the backside
				
				rangePosition = (YapDatabaseViewRangePosition){
					.offsetFromBeginning = rangeOffset,
					.offsetFromEnd = 0,
					.length = 0
				};
			}
		}
		else
		{
			// Offset is from end (index last)
			
			NSUInteger reverseOffset = rangeOffset + rangeLength;
			
			if (reverseOffset <= groupCount)
			{
				// Valid range
				
				rangePosition = (YapDatabaseViewRangePosition){
					.offsetFromBeginning = groupCount - reverseOffset,
					.offsetFromEnd = rangeOffset,
					.length = rangeLength
				};
			}
			else
			{
				// Range fell off the backside
				
				rangePosition = (YapDatabaseViewRangePosition){
					.offsetFromBeginning = 0,
					.offsetFromEnd = rangeOffset,
					.length = 0,
				};
			}
		}
	}
	else
	{
		rangePosition = (YapDatabaseViewRangePosition){
			.offsetFromBeginning = 0,
			.offsetFromEnd = 0,
			.length = groupCount
		};
	}
	
	if ([reverse containsObject:group])
	{
		NSUInteger swap = rangePosition.offsetFromEnd;
		rangePosition.offsetFromEnd = rangePosition.offsetFromBeginning;
		rangePosition.offsetFromBeginning = swap;
	}
	
	return rangePosition;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Getters + Total
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Returns the total number of items by summing up the totals across all groups.
**/
- (NSUInteger)numberOfItemsInAllGroups
{
	if (snapshotOfLastUpdate == UINT64_MAX) return 0;
	
	NSUInteger total = 0;
	
	for (NSString *group in visibleGroups)
	{
		YapDatabaseViewRangeOptions *rangeOpts = [rangeOptions objectForKey:group];
		if (rangeOpts)
		{
			total += rangeOpts.length;
		}
		else
		{
			total += [[counts objectForKey:group] unsignedIntegerValue];
		}
	}
	
	return total;
}

/**
 * This method is useful if you ever want to display multiple groups in a tableView,
 * but you want to display the groups without using sections.
 * 
 * For example, say you have a view that sorts users in an address book.
 * The view uses groups based on the first letter of the user's name.
 * But you want to display the address book in a tableView without using sections.
 * 
 * view = @{
 *   @"A" = @[ @"Alice" ]
 *   @"B" = @[ @"Barney", @"Bob" ]
 *   @"C" = @[ @"Chris" ]
 * }
 * 
 * NSString *group = nil;
 * NSUInteger index = 0;
 *
 * [mappings getGroup:&group index:&index forUnSectionedRow:2];
 * 
 * // group = @"B"
 * // index = 1    (Bob)
 *
 * [mappings getGroup:&group index:&index forUnSectionedRow:3];
 *
 * // group = @"C"
 * // index = 0    (Chris)
**/
- (BOOL)getGroup:(NSString **)groupPtr index:(NSUInteger *)indexPtr forUnSectionedRow:(NSUInteger)row
{
	if (snapshotOfLastUpdate == UINT64_MAX)
	{
		if (groupPtr) *groupPtr = nil;
		if (indexPtr) *indexPtr = 0;
		return NO;
	}
	
	NSUInteger offset = 0;
	
	for (NSString *group in visibleGroups)
	{
		NSUInteger count = [self visibleCountForGroup:group];
		
		if ((row < (offset + count)) && (count > 0))
		{
			NSUInteger index = [self indexForRow:(row - offset) inGroup:group];
			
			if (groupPtr) *groupPtr = group;
			if (indexPtr) *indexPtr = index;
			
			return YES;
		}
		
		offset += count;
	}
	
	if (groupPtr) *groupPtr = nil;
	if (indexPtr) *indexPtr = 0;
	return NO;
}

/**
 * This method is useful if you ever want to display multiple groups in a tableView,
 * but you want to display the groups without using sections.
**/
- (BOOL)getUnSectionedRow:(NSUInteger *)rowPtr forIndex:(NSUInteger)index inGroup:(NSString *)group
{
	NSUInteger groupOffset = 0;
	
	for (NSString *visibleGroup in visibleGroups)
	{
		if ([visibleGroup isEqualToString:group])
		{
			NSUInteger row = [self rowForIndex:index inGroup:group];
			
			if (row == NSNotFound)
			{
				if (rowPtr) *rowPtr = 0;
				return NO;
			}
			else
			{
				if (rowPtr) *rowPtr = (groupOffset + row);
				return YES;
			}
		}
		else
		{
			groupOffset += [self visibleCountForGroup:visibleGroup];
		}
	}
	
	if (rowPtr) *rowPtr = 0;
	return NO;
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
