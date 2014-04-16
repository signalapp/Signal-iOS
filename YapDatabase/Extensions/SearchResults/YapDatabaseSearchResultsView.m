#import "YapDatabaseSearchResultsView.h"
#import "YapDatabaseSearchResultsViewPrivate.h"
#import "YapDatabaseExtensionPrivate.h"
#import "YapDatabaseFullTextSearch.h"
#import "YapDatabasePrivate.h"
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


@implementation YapDatabaseSearchResultsView

+ (void)dropTablesForRegisteredName:(NSString *)registeredName
                    withTransaction:(YapDatabaseReadWriteTransaction *)transaction
{
	NSString *snippetTableName = [self snippetTableNameForRegisteredName:registeredName];
	
	// Handle persistent view
	
	sqlite3 *db = transaction->connection->db;
	
	NSString *dropTable = [NSString stringWithFormat:@"DROP TABLE IF EXISTS \"%@\";", snippetTableName];
	
	int status = sqlite3_exec(db, [dropTable UTF8String], NULL, NULL, NULL);
	if (status != SQLITE_OK)
	{
		YDBLogError(@"%@ - Failed dropping snippet table (%@): %d %s",
		            THIS_METHOD, snippetTableName, status, sqlite3_errmsg(db));
	}
	
	// Handle memory view
	
	[transaction->connection unregisterTableWithName:snippetTableName];
}

+ (NSString *)snippetTableNameForRegisteredName:(NSString *)registeredName
{
	return [NSString stringWithFormat:@"view_%@_snippet", registeredName];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Invalid
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (id)initWithGroupingBlock:(YapDatabaseViewGroupingBlock)inGroupingBlock
          groupingBlockType:(YapDatabaseViewBlockType)inGroupingBlockType
               sortingBlock:(YapDatabaseViewSortingBlock)inSortingBlock
           sortingBlockType:(YapDatabaseViewBlockType)inSortingBlockType
                 versionTag:(NSString *)inVersionTag
                    options:(YapDatabaseViewOptions *)inOptions
{
	NSString *reason = @"You must use the init method(s) specific to YapDatabaseSearchResults.";
	
	NSDictionary *userInfo = @{ NSLocalizedRecoverySuggestionErrorKey:
	    @"YapDatabaseSearchResults is designed to pipe search results from YapDatabaseFullTextSearch into"
		@" a YapDatabaseView. Thus it needs different information which is specific to this task."
		@" As such, YapDatabaseSearchResults has different init methods you must use."};
	
	@throw [NSException exceptionWithName:@"YapDatabaseException" reason:reason userInfo:userInfo];
	
	return nil;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Instance
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@synthesize parentViewName = parentViewName;
@synthesize fullTextSearchName = fullTextSearchName;

- (id)initWithFullTextSearchName:(NSString *)inFullTextSearchName
                  parentViewName:(NSString *)inParentViewName
					  versionTag:(NSString *)inVersionTag
						 options:(YapDatabaseSearchResultsViewOptions *)inOptions
{
	NSAssert(inFullTextSearchName != nil, @"Invalid fullTextSearchName");
	NSAssert(inParentViewName != nil, @"Invalid parentViewName");
	
	if ((self = [super init]))
	{
		fullTextSearchName = [inFullTextSearchName copy];
		parentViewName = [inParentViewName copy];
		
		versionTag = inVersionTag ? [inVersionTag copy] : @"";
		
		options = inOptions ? [inOptions copy] : [[YapDatabaseSearchResultsViewOptions alloc] init];
	}
	return self;
}

- (id)initWithFullTextSearchName:(NSString *)inFullTextSearchName
                   groupingBlock:(YapDatabaseViewGroupingBlock)inGroupingBlock
               groupingBlockType:(YapDatabaseViewBlockType)inGroupingBlockType
                    sortingBlock:(YapDatabaseViewSortingBlock)inSortingBlock
                sortingBlockType:(YapDatabaseViewBlockType)inSortingBlockType
                      versionTag:(NSString *)inVersionTag
                         options:(YapDatabaseSearchResultsViewOptions *)inOptions
{
	NSAssert(inFullTextSearchName != nil, @"Invalid fullTextSearchName");
	
	NSAssert(inGroupingBlock != NULL, @"Invalid grouping block");
	NSAssert(inSortingBlock != NULL, @"Invalid sorting block");
	
	NSAssert(inGroupingBlockType == YapDatabaseViewBlockTypeWithKey ||
	         inGroupingBlockType == YapDatabaseViewBlockTypeWithObject ||
	         inGroupingBlockType == YapDatabaseViewBlockTypeWithMetadata ||
	         inGroupingBlockType == YapDatabaseViewBlockTypeWithRow,
	         @"Invalid grouping block type");
	
	NSAssert(inSortingBlockType == YapDatabaseViewBlockTypeWithKey ||
	         inSortingBlockType == YapDatabaseViewBlockTypeWithObject ||
	         inSortingBlockType == YapDatabaseViewBlockTypeWithMetadata ||
	         inSortingBlockType == YapDatabaseViewBlockTypeWithRow,
	         @"Invalid sorting block type");
	
	if ((self = [super init]))
	{
		fullTextSearchName = [inFullTextSearchName copy];
		
		groupingBlock = inGroupingBlock;
		groupingBlockType = inGroupingBlockType;
		
		sortingBlock = inSortingBlock;
		sortingBlockType = inSortingBlockType;
		
		versionTag = inVersionTag ? [inVersionTag copy] : @"";
		
		options = inOptions ? [inOptions copy] : [[YapDatabaseSearchResultsViewOptions alloc] init];
	}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Registration
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)supportsDatabase:(YapDatabase *)database withRegisteredExtensions:(NSDictionary *)registeredExtensions
{
	if (![super supportsDatabase:database withRegisteredExtensions:registeredExtensions])
		return NO;
	
	YapDatabaseExtension *ext = [registeredExtensions objectForKey:fullTextSearchName];
	if (ext == nil)
	{
		YDBLogWarn(@"The specified fullTextSearchName (%@) isn't registered", fullTextSearchName);
		return NO;
	}
	
	if (![ext isKindOfClass:[YapDatabaseFullTextSearch class]])
	{
		YDBLogWarn(@"The specified fullTextSearchName (%@) isn't a YapDatabaseFullTextSearch extension",
				   fullTextSearchName);
		return NO;
	}
	
	if (parentViewName)
	{
		ext = [registeredExtensions objectForKey:parentViewName];
		if (ext == nil)
		{
			YDBLogWarn(@"The specified parentViewName (%@) isn't registered", parentViewName);
			return NO;
		}
		
		if (![ext isKindOfClass:[YapDatabaseView class]])
		{
			YDBLogWarn(@"The specified parentViewName (%@) isn't a YapDatabaseView extension", parentViewName);
			return NO;
		}
		
		// Capture grouping & sorting block
		
		__unsafe_unretained YapDatabaseView *parentView = (YapDatabaseView *)ext;
		
		groupingBlock = parentView->groupingBlock;
		groupingBlockType = parentView->groupingBlockType;
		
		sortingBlock = parentView->sortingBlock;
		sortingBlockType = parentView->sortingBlockType;
	}
	
	return YES;
}

- (NSSet *)dependencies
{
	if (parentViewName) {
		return [NSSet setWithObjects:fullTextSearchName, parentViewName, nil];
	}
	else {
		return [NSSet setWithObject:fullTextSearchName];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Connections
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (YapDatabaseExtensionConnection *)newConnection:(YapDatabaseConnection *)databaseConnection
{
	return [[YapDatabaseSearchResultsViewConnection alloc] initWithView:self databaseConnection:databaseConnection];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Internal
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)snippetTableName
{
	return [[self class] snippetTableNameForRegisteredName:self.registeredName];
}

@end
