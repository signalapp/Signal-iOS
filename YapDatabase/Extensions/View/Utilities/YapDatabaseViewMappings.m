#import "YapDatabaseViewMappingsPrivate.h"

#import "YapAbstractDatabaseConnection.h"
#import "YapAbstractDatabaseTransaction.h"

#import "YapDatabaseView.h"
#import "YapCollectionsDatabaseViewTransaction.h"


@implementation YapDatabaseViewMappings
{
	NSArray *allGroups;
	NSString *registeredViewName;
	
	NSMutableArray *visibleGroups;
	NSMutableDictionary *counts;
	
	NSMutableDictionary *allowsEmptySection;
	
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
		
		visibleGroups = [[NSMutableArray alloc] initWithCapacity:[allGroups count]];
		
		id sharedKeySet = [NSDictionary sharedKeySetForKeys:allGroups];
		
		counts = [NSMutableDictionary dictionaryWithSharedKeySet:sharedKeySet];
		allowsEmptySection = [NSMutableDictionary dictionaryWithSharedKeySet:sharedKeySet];
		
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
	
	copy->allowsEmptySection = [allowsEmptySection mutableCopy];
	
	copy->snapshotOfLastUpdate = snapshotOfLastUpdate;
	
	return copy;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Configuration
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)allowsEmptySectionForAllGroups
{
	return ([allowsEmptySection count] == [allGroups count]);
}

- (void)setAllowsEmptySectionForAllGroups:(BOOL)globalAllowsEmptySections
{
	if (globalAllowsEmptySections)
	{
		for (NSString *group in allGroups)
		{
			[allowsEmptySection setObject:@(YES) forKey:group];
		}
	}
	else
	{
		[allowsEmptySection removeAllObjects];
	}
}

- (BOOL)allowsEmptySectionForGroup:(NSString *)group
{
	return [[allowsEmptySection objectForKey:group] boolValue];
}

- (void)setAllowsEmptySection:(BOOL)flag forGroup:(NSString *)group
{
	if (flag)
		[allowsEmptySection setObject:@(YES) forKey:group];
	else
		[allowsEmptySection removeObjectForKey:group];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Initialization & Updates
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)updateWithTransaction:(YapAbstractDatabaseTransaction *)transaction
{
	[visibleGroups removeAllObjects];
	
	for (NSString *group in allGroups)
	{
		NSUInteger count = [[transaction ext:registeredViewName] numberOfKeysInGroup:group];
		
		if (count > 0 || [[allowsEmptySection objectForKey:group] boolValue]) {
			[visibleGroups addObject:group];
		}
		
		[counts setObject:@(count) forKey:group];
	}
	
	snapshotOfLastUpdate = transaction.abstractConnection.snapshot;
}

/**
 * This method is internal.
 * It is only for use by the unit tests in TestViewChangeLogic.
**/
- (void)updateWithCounts:(NSDictionary *)newCounts
{
	[visibleGroups removeAllObjects];
	
	for (NSString *group in allGroups)
	{
		NSUInteger count = [[newCounts objectForKey:group] unsignedIntegerValue];
		
		if (count > 0 || [[allowsEmptySection objectForKey:group] boolValue])
			[visibleGroups addObject:group];
		
		[counts setObject:@(count) forKey:group];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Getters
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSUInteger)numberOfSections
{
	return [visibleGroups count];
}

- (NSUInteger)numberOfItemsInSection:(NSUInteger)section
{
	return [[counts objectForKey:[self groupForSection:section]] unsignedIntegerValue];
}

- (NSUInteger)numberOfItemsInGroup:(NSString *)group
{
	return [[counts objectForKey:group] unsignedIntegerValue];
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
