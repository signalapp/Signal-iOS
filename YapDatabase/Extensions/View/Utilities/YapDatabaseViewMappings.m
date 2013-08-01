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

- (void)setRange:(NSRange)range hard:(BOOL)isHardRange pinnedTo:(YapDatabaseViewPin)pin forGroup:(NSString *)group
{
	if (![allGroups containsObject:group]) {
		YDBLogWarn(@"%@ - mappings doesn't contain group(%@), only: %@", THIS_METHOD, group, allGroups);
		return;
	}
	
	// Validate range
	
	NSUInteger count = [[counts objectForKey:group] unsignedIntegerValue];
	
	if ((range.length == 0) || (range.location + range.length >= count))
	{
		YDBLogWarn(@"%@ - invalid range(%@) for group(%@)", THIS_METHOD, NSStringFromRange(range), group);
		return;
	}
	
	// Add to dictionary
	
	YapDatabaseViewMappingsRangeOptions *rangeOpts =
	    [[YapDatabaseViewMappingsRangeOptions alloc] initWithRange:range hard:isHardRange pin:pin];
	
	[rangeOptions setObject:rangeOpts forKey:group];
}

- (void)setRangeOptions:(YapDatabaseViewMappingsRangeOptions *)rangeOpts forGroup:(NSString *)group
{
	[rangeOptions setObject:rangeOpts forKey:group];
}

- (void)removeRangeOptionsForGroup:(NSString *)group
{
	[rangeOptions removeObjectForKey:group];
}

- (BOOL)getRange:(NSRange *)rangePtr
            hard:(BOOL *)isHardRangePtr
        pinnedTo:(YapDatabaseViewPin *)pinPtr
        forGroup:(NSString *)group
{
	YapDatabaseViewMappingsRangeOptions *rangeOpts = [rangeOptions objectForKey:group];
	
	if (rangeOpts)
	{
		if (rangePtr) *rangePtr = rangeOpts.range;
		if (isHardRangePtr) *isHardRangePtr = rangeOpts.isHardRange;
		if (pinPtr) *pinPtr = rangeOpts.pin;
		
		return YES;
	}
	else
	{
		if (rangePtr) *rangePtr = NSMakeRange(0, 0);
		if (isHardRangePtr) *isHardRangePtr = NO;
		if (pinPtr) *pinPtr = YapDatabaseViewBeginning;
		
		return NO;
	}
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
		
		if (count > 0 || ![dynamicSections containsObject:group]) {
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
		
		if (count > 0 || ![dynamicSections containsObject:group])
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

/**
 * This method is for internal use only.
**/
- (NSDictionary *)rangeOptions
{
	return [rangeOptions copy];
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

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation YapDatabaseViewMappingsRangeOptions

@synthesize range = range;
@synthesize isHardRange = isHardRange;
@synthesize pin = pin;

- (id)initWithRange:(NSRange)inRange hard:(BOOL)inIsHardRange pin:(YapDatabaseViewPin)inPin
{
	if ((self = [super init]))
	{
		range = inRange;
		isHardRange = inIsHardRange;
		
		// Enforce proper pin value
		if (inPin == YapDatabaseViewBeginning)
			pin = YapDatabaseViewBeginning;
		else
			pin = YapDatabaseViewEnd;
	}
	return self;
}

@end
