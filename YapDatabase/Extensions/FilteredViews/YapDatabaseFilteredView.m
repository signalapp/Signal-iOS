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
#pragma unused(ydbLogLevel)


@implementation YapDatabaseFilteredView

@synthesize parentViewName = parentViewName;
@synthesize filtering = filtering;

@dynamic options;

#pragma mark Invalid

- (instancetype)initWithGrouping:(YapDatabaseViewGrouping __unused *)inGrouping
                         sorting:(YapDatabaseViewSorting __unused *)inSorting
                      versionTag:(NSString __unused *)inVersionTag
                         options:(YapDatabaseViewOptions __unused *)inOptions
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
                   filtering:(YapDatabaseViewFiltering *)inFiltering
{
	return [self initWithParentViewName:inParentViewName filtering:inFiltering versionTag:nil options:nil];
}

- (id)initWithParentViewName:(NSString *)inParentViewName
                   filtering:(YapDatabaseViewFiltering *)inFiltering
                  versionTag:(NSString *)inVersionTag
{
	return [self initWithParentViewName:inParentViewName filtering:inFiltering versionTag:inVersionTag options:nil];
}

- (id)initWithParentViewName:(NSString *)inParentViewName
                   filtering:(YapDatabaseViewFiltering *)inFiltering
                  versionTag:(NSString *)inVersionTag
                     options:(YapDatabaseViewOptions *)inOptions
{
	NSAssert(inParentViewName != nil, @"Invalid parameter: parentViewName == nil");
	NSAssert([inFiltering isKindOfClass:[YapDatabaseViewFiltering class]], @"Invalid parameter: filtering");
	
	if ((self = [super init]))
	{
		parentViewName = [inParentViewName copy];
		
		filtering = inFiltering;
		
		versionTag = inVersionTag ? [inVersionTag copy] : @"";
		
		options = inOptions ? [inOptions copy] : [[YapDatabaseViewOptions alloc] init];
	}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Custom Getters
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (YapDatabaseViewFiltering *)filtering
{
	// This property can be changed from within a readWriteTransaction.
	// We go through the snapshot queue to ensure we're fetching the most recent value.
	
	__block YapDatabaseViewFiltering *mostRecentFiltering = nil;
	dispatch_block_t block = ^{
		
		mostRecentFiltering = filtering;
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
	
	return mostRecentFiltering;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Registration
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)supportsDatabaseWithRegisteredExtensions:(NSDictionary<NSString*, YapDatabaseExtension*> *)registeredExtensions
{
	if (![super supportsDatabaseWithRegisteredExtensions:registeredExtensions])
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
	
	grouping = parentView->grouping;
	sorting = parentView->sorting;
	
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
	
	YapDatabaseViewFiltering *newFiltering = changeset[changeset_key_filtering];
	if (newFiltering)
	{
		filtering = newFiltering;
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Internal
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Used by YapDatabaseFilteredViewConnection to fetch & cache the values for a readWriteTransaction.
**/
- (void)getGrouping:(YapDatabaseViewGrouping **)groupingPtr
            sorting:(YapDatabaseViewSorting **)sortingPtr
          filtering:(YapDatabaseViewFiltering **)filteringPtr
{
	__block YapDatabaseViewGrouping  * mostRecentGrouping  = nil;
	__block YapDatabaseViewSorting   * mostRecentSorting   = nil;
	__block YapDatabaseViewFiltering * mostRecentFiltering = nil;
	
	dispatch_block_t block = ^{
	
		mostRecentGrouping  = grouping;
		mostRecentSorting   = sorting;
		mostRecentFiltering = filtering;
	};
	
	__strong YapDatabase *database = self.registeredDatabase;
	if (database)
	{
		if (dispatch_get_specific(database->IsOnSnapshotQueueKey))
			block();
		else
			dispatch_sync(database->snapshotQueue, block);
	}
	
	if (groupingPtr)  *groupingPtr  = mostRecentGrouping;
	if (sortingPtr)   *sortingPtr   = mostRecentSorting;
	if (filteringPtr) *filteringPtr = mostRecentFiltering;
}

@end
