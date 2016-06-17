#import "YapDatabaseAutoView.h"
#import "YapDatabaseAutoViewPrivate.h"

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
#pragma unused(ydbLogLevel)


@implementation YapDatabaseAutoView

+ (NSArray *)previousClassNames
{
	return @[ @"YapCollectionsDatabaseView" ];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Instance
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@synthesize grouping = grouping;
@synthesize sorting = sorting;

#pragma mark Init

- (instancetype)initWithGrouping:(YapDatabaseViewGrouping *)inGrouping
                         sorting:(YapDatabaseViewSorting *)inSorting
{
	return [self initWithGrouping:inGrouping
	                      sorting:inSorting
	                   versionTag:nil
	                      options:nil];
}

- (instancetype)initWithGrouping:(YapDatabaseViewGrouping *)inGrouping
                         sorting:(YapDatabaseViewSorting *)inSorting
                      versionTag:(NSString *)inVersionTag
{
	return [self initWithGrouping:inGrouping
	                      sorting:inSorting
	                   versionTag:inVersionTag
	                      options:nil];
}

- (instancetype)initWithGrouping:(YapDatabaseViewGrouping *)inGrouping
                         sorting:(YapDatabaseViewSorting *)inSorting
                      versionTag:(NSString *)inVersionTag
                         options:(YapDatabaseViewOptions *)inOptions
{
	NSAssert([inGrouping isKindOfClass:[YapDatabaseViewGrouping class]], @"Invalid parameter: grouping");
	NSAssert([inSorting isKindOfClass:[YapDatabaseViewSorting class]], @"Invalid parameter: sorting");
	
	if ((self = [super initWithVersionTag:inVersionTag options:inOptions]))
	{
		grouping = inGrouping;
		sorting = inSorting;
	}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark YapDatabaseExtension Protocol
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (YapDatabaseExtensionConnection *)newConnection:(YapDatabaseConnection *)databaseConnection
{
	return [[YapDatabaseAutoViewConnection alloc] initWithParent:self databaseConnection:databaseConnection];
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
	
	YapDatabaseViewGrouping *newGrouping = changeset[changeset_key_grouping];
	if (newGrouping)
	{
		grouping = newGrouping;
	}
	
	YapDatabaseViewSorting *newSorting = changeset[changeset_key_sorting];
	if (newSorting)
	{
		sorting = newSorting;
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Internal
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Used by YapDatabaseViewConnection to fetch & cache the values for a readWriteTransaction.
**/
- (void)getGrouping:(YapDatabaseViewGrouping **)groupingPtr
            sorting:(YapDatabaseViewSorting **)sortingPtr
{
	__block YapDatabaseViewGrouping *mostRecentGrouping = nil;
	__block YapDatabaseViewSorting  *mostRecentSorting  = nil;
	
	dispatch_block_t block = ^{
	
		mostRecentGrouping = grouping;
		mostRecentSorting  = sorting;
	};
	
	__strong YapDatabase *database = self.registeredDatabase;
	if (database)
	{
		if (dispatch_get_specific(database->IsOnSnapshotQueueKey))
			block();
		else
			dispatch_sync(database->snapshotQueue, block);
	}
	
	if (groupingPtr) *groupingPtr = mostRecentGrouping;
	if (sortingPtr)  *sortingPtr  = mostRecentSorting;
}

@end
