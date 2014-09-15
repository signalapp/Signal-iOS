#import "YapDatabaseFilteredView.h"
#import "YapDatabaseFilteredViewPrivate.h"
#import "YapDatabasePrivate.h"
#import "YapDatabaseExtensionPrivate.h"
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


@implementation YapDatabaseFilteredView

@synthesize parentViewName = parentViewName;

@synthesize filteringBlock = filteringBlock;
@synthesize filteringBlockType = filteringBlockType;

#pragma mark Invalid

- (instancetype)initWithGrouping:(YapDatabaseViewGrouping *)grouping
                         sorting:(YapDatabaseViewSorting *)sorting
                      versionTag:(NSString *)inVersionTag
                         options:(YapDatabaseViewOptions *)inOptions
{
	NSString *reason = @"You must use the init method(s) specific to YapDatabaseFilteredView.";
	
	NSDictionary *userInfo = @{ NSLocalizedRecoverySuggestionErrorKey:
	    @"YapDatabaseFilteredView is designed to filter an existing YapDatabaseView instance."
		@" Thus it needs to know the registeredName of the YapDatabaseView instance you wish to filter."
		@" As such, YapDatabaseFilteredView has different init methods you must use."};
	
	@throw [NSException exceptionWithName:@"YapDatabaseException" reason:reason userInfo:userInfo];
	
	return nil;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Init
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (id)initWithParentViewName:(NSString *)inParentViewName
                   filtering:(YapDatabaseViewFiltering *)filtering
{
	return [self initWithParentViewName:inParentViewName filtering:filtering versionTag:nil options:nil];
}

- (id)initWithParentViewName:(NSString *)inParentViewName
                   filtering:(YapDatabaseViewFiltering *)filtering
                  versionTag:(NSString *)inVersionTag
{
	return [self initWithParentViewName:inParentViewName filtering:filtering versionTag:inVersionTag options:nil];
}

- (id)initWithParentViewName:(NSString *)inParentViewName
                   filtering:(YapDatabaseViewFiltering *)filtering
                  versionTag:(NSString *)inVersionTag
                     options:(YapDatabaseViewOptions *)inOptions
{
	NSAssert(inParentViewName != nil, @"Invalid parameter: parentViewName == nil");
	NSAssert(filtering != nil, @"Invalid parameter: filtering == nil");
	
	if ((self = [super init]))
	{
		parentViewName = [inParentViewName copy];
		
		filteringBlock = filtering.filteringBlock;
		filteringBlockType = filtering.filteringBlockType;
		
		versionTag = inVersionTag ? [inVersionTag copy] : @"";
		
		options = inOptions ? [inOptions copy] : [[YapDatabaseViewOptions alloc] init];
	}
	return self;
}

/**
 * DEPRECATED
 * Use method initWithParentViewName:filtering: instead.
**/
- (id)initWithParentViewName:(NSString *)inParentViewName
              filteringBlock:(YapDatabaseViewFilteringBlock)inBlock
          filteringBlockType:(YapDatabaseViewBlockType)inBlockType
{
	YapDatabaseViewFiltering *filtering = [YapDatabaseViewFiltering withBlock:inBlock blockType:inBlockType];
	
	return [self initWithParentViewName:inParentViewName
	                          filtering:filtering
	                         versionTag:nil
	                            options:nil];
}

/**
 * DEPRECATED
 * Use method initWithParentViewName:filtering:versionTag: instead.
**/
- (id)initWithParentViewName:(NSString *)inParentViewName
              filteringBlock:(YapDatabaseViewFilteringBlock)inBlock
          filteringBlockType:(YapDatabaseViewBlockType)inBlockType
                  versionTag:(NSString *)inVersionTag
{
	YapDatabaseViewFiltering *filtering = [YapDatabaseViewFiltering withBlock:inBlock blockType:inBlockType];
	
	return [self initWithParentViewName:inParentViewName
	                          filtering:filtering
	                         versionTag:inVersionTag
	                            options:nil];
}

/**
 * DEPRECATED
 * Use method initWithParentViewName:filtering:versionTag:options: instead.
**/
- (id)initWithParentViewName:(NSString *)inParentViewName
              filteringBlock:(YapDatabaseViewFilteringBlock)inBlock
          filteringBlockType:(YapDatabaseViewBlockType)inBlockType
                  versionTag:(NSString *)inVersionTag
                     options:(YapDatabaseViewOptions *)inOptions
{
	YapDatabaseViewFiltering *filtering = [YapDatabaseViewFiltering withBlock:inBlock blockType:inBlockType];
	
	return [self initWithParentViewName:inParentViewName
	                          filtering:filtering
	                         versionTag:inVersionTag
	                            options:inOptions];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Custom Getters
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (YapDatabaseViewFilteringBlock)filteringBlock
{
	// This property can be changed from within a readWriteTransaction.
	// We go through the snapshot queue to ensure we're fetching the most recent value.
	
	__block YapDatabaseViewFilteringBlock mostRecentFilteringBlock = NULL;
	dispatch_block_t block = ^{
		
		mostRecentFilteringBlock = filteringBlock;
	};
	
	__strong YapDatabase *database = self.registeredDatabase;
	if (database)
	{
		if (dispatch_get_specific(database->IsOnSnapshotQueueKey))
			block();
		else
			dispatch_sync(database->snapshotQueue, block);
	}
	else // not registered
	{
		block();
	}
	
	return mostRecentFilteringBlock;
}

- (YapDatabaseViewBlockType)filteringBlockType
{
	// This property can be changed from within a readWriteTransaction.
	// We go through the snapshot queue to ensure we're fetching the most recent value.
	
	__block YapDatabaseViewBlockType mostRecentFilteringBlockType = 0;
	dispatch_block_t block = ^{
		
		mostRecentFilteringBlockType = filteringBlockType;
	};
	
	__strong YapDatabase *database = self.registeredDatabase;
	if (database)
	{
		if (dispatch_get_specific(database->IsOnSnapshotQueueKey))
			block();
		else
			dispatch_sync(database->snapshotQueue, block);
	}
	else // not registered
	{
		block();
	}
	
	return mostRecentFilteringBlockType;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Registration
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)supportsDatabase:(YapDatabase *)database withRegisteredExtensions:(NSDictionary *)registeredExtensions
{
	if (![super supportsDatabase:database withRegisteredExtensions:registeredExtensions])
		return NO;
	
	YapDatabaseExtension *ext = [registeredExtensions objectForKey:parentViewName];
	if (ext == nil)
	{
		YDBLogWarn(@"The specified parentViewName (%@) isn't registered", parentViewName);
		return NO;
	}
	
	if (![ext isKindOfClass:[YapDatabaseView class]])
	{
		YDBLogWarn(@"The specified parentViewName (%@) isn't a view", parentViewName);
		return NO;
	}
	
	// Capture grouping & sorting block
	
	__unsafe_unretained YapDatabaseView *parentView = (YapDatabaseView *)ext;
	
	groupingBlock = parentView->groupingBlock;
	groupingBlockType = parentView->groupingBlockType;
	
	sortingBlock = parentView->sortingBlock;
	sortingBlockType = parentView->sortingBlockType;
	
	return YES;
}

- (NSSet *)dependencies
{
	return [NSSet setWithObject:parentViewName];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Connections
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (YapDatabaseExtensionConnection *)newConnection:(YapDatabaseConnection *)databaseConnection
{
	return [[YapDatabaseFilteredViewConnection alloc] initWithView:self databaseConnection:databaseConnection];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Changeset
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Subclasses may OPTIONALLY implement this method.
 *
 * This method is invoked on the snapshot queue.
 * The given changeset is the most recent commit.
**/
- (void)processChangeset:(NSDictionary *)changeset
{
	YDBLogAutoTrace();
	
	[super processChangeset:changeset];
	
	YapDatabaseViewFilteringBlock newFilteringBlock = changeset[changeset_key_filteringBlock];
	if (newFilteringBlock)
	{
		filteringBlock = newFilteringBlock;
		filteringBlockType = [changeset[changeset_key_filteringBlockType] integerValue];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Internal
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Used by YapDatabaseFilteredViewConnection to fetch & cache the values for a readWriteTransaction.
**/
- (void)getGroupingBlock:(YapDatabaseViewGroupingBlock *)groupingBlockPtr
       groupingBlockType:(YapDatabaseViewBlockType *)groupingBlockTypePtr
            sortingBlock:(YapDatabaseViewSortingBlock *)sortingBlockPtr
        sortingBlockType:(YapDatabaseViewBlockType *)sortingBlockTypePtr
          filteringBlock:(YapDatabaseViewFilteringBlock *)filteringBlockPtr
      filteringBlockType:(YapDatabaseViewBlockType *)filteringBlockTypePtr
{
	__block YapDatabaseViewGroupingBlock  mostRecentGroupingBlock  = NULL;
	__block YapDatabaseViewSortingBlock   mostRecentSortingBlock   = NULL;
	__block YapDatabaseViewFilteringBlock mostRecentFilteringBlock = NULL;
	__block YapDatabaseViewBlockType mostRecentGroupingBlockType  = 0;
	__block YapDatabaseViewBlockType mostRecentSortingBlockType   = 0;
	__block YapDatabaseViewBlockType mostRecentFilteringBlockType = 0;
	
	dispatch_block_t block = ^{
	
		mostRecentGroupingBlock      = groupingBlock;
		mostRecentGroupingBlockType  = groupingBlockType;
		mostRecentSortingBlock       = sortingBlock;
		mostRecentSortingBlockType   = sortingBlockType;
		mostRecentFilteringBlock     = filteringBlock;
		mostRecentFilteringBlockType = filteringBlockType;
	};
	
	__strong YapDatabase *database = self.registeredDatabase;
	if (database)
	{
		if (dispatch_get_specific(database->IsOnSnapshotQueueKey))
			block();
		else
			dispatch_sync(database->snapshotQueue, block);
	}
	
	if (groupingBlockPtr)      *groupingBlockPtr      = mostRecentGroupingBlock;
	if (groupingBlockTypePtr)  *groupingBlockTypePtr  = mostRecentGroupingBlockType;
	if (sortingBlockPtr)       *sortingBlockPtr       = mostRecentSortingBlock;
	if (sortingBlockTypePtr)   *sortingBlockTypePtr   = mostRecentSortingBlockType;
	if (filteringBlockPtr)     *filteringBlockPtr     = mostRecentFilteringBlock;
	if (filteringBlockTypePtr) *filteringBlockTypePtr = mostRecentFilteringBlockType;
}

@end
