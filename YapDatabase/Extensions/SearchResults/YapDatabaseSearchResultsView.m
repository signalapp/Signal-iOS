#import "YapDatabaseSearchResultsView.h"
#import "YapDatabaseSearchResultsViewPrivate.h"
#import "YapDatabaseExtensionPrivate.h"
#import "YapDatabaseFullTextSearch.h"
#import "YapDatabaseViewPrivate.h"
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
#pragma unused(ydbLogLevel)


@implementation YapDatabaseSearchResultsView

+ (void)dropTablesForRegisteredName:(NSString *)registeredName
                    withTransaction:(YapDatabaseReadWriteTransaction *)transaction
                      wasPersistent:(BOOL)wasPersistent
{
	NSString *snippetTableName = [self snippetTableNameForRegisteredName:registeredName];
	
	if (wasPersistent)
	{
		// Handle persistent view
		
		sqlite3 *db = transaction->connection->db;
		
		NSString *dropTable = [NSString stringWithFormat:@"DROP TABLE IF EXISTS \"%@\";", snippetTableName];
		
		int status = sqlite3_exec(db, [dropTable UTF8String], NULL, NULL, NULL);
		if (status != SQLITE_OK)
		{
			YDBLogError(@"%@ - Failed dropping snippet table (%@): %d %s",
			            THIS_METHOD, snippetTableName, status, sqlite3_errmsg(db));
		}
	}
	else
	{
		// Handle memory view
		
		[transaction->connection unregisterMemoryTableWithName:snippetTableName];
	}
}

+ (NSString *)snippetTableNameForRegisteredName:(NSString *)registeredName
{
	return [NSString stringWithFormat:@"view_%@_snippet", registeredName];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Invalid
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (instancetype)initWithGrouping:(YapDatabaseViewGrouping __unused *)grouping
                         sorting:(YapDatabaseViewSorting __unused *)sorting
                      versionTag:(NSString __unused *)inVersionTag
                         options:(YapDatabaseViewOptions __unused *)inOptions
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
                        grouping:(YapDatabaseViewGrouping *)inGrouping
                         sorting:(YapDatabaseViewSorting *)inSorting
                      versionTag:(NSString *)inVersionTag
                         options:(YapDatabaseSearchResultsViewOptions *)inOptions
{
	NSAssert(inFullTextSearchName != nil, @"Invalid parameter: fullTextSearchName == nil");
	
	NSAssert([inGrouping isKindOfClass:[YapDatabaseViewGrouping class]], @"Invalid parameter: grouping");
	NSAssert([inSorting isKindOfClass:[YapDatabaseViewSorting class]], @"Invalid parameter: sorting");
	
	if ((self = [super init]))
	{
		fullTextSearchName = [inFullTextSearchName copy];
		
		grouping = inGrouping;
		sorting = inSorting;
		
		versionTag = inVersionTag ? [inVersionTag copy] : @"";
		
		options = inOptions ? [inOptions copy] : [[YapDatabaseSearchResultsViewOptions alloc] init];
	}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Registration
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * YapDatabaseExtension subclasses may OPTIONALLY implement this method.
 * This method is called during the extension registration process to enusre the extension (as configured)
 * will support the given database configuration. This is primarily for extensions with dependecies.
 *
 * For example, the YapDatabaseFilteredView is configured with the registered name of a parent View instance.
 * So that class should implement this method to ensure:
 * - The parentView actually exists
 * - The parentView is actually a YapDatabaseView class/subclass
 *
 * When this method is invoked, the 'self.registeredName' & 'self.registeredDatabase' properties
 * will be set and available for inspection.
 *
 * @param registeredExtensions
 *   The current set of registered extensions. (i.e. self.registeredDatabase.registeredExtensions)
 *
 * Return YES if the class/instance supports the database configuration.
**/
- (BOOL)supportsDatabaseWithRegisteredExtensions:(NSDictionary *)registeredExtensions
{
	if (![super supportsDatabaseWithRegisteredExtensions:registeredExtensions])
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
		
		grouping = parentView->grouping;
		sorting = parentView->sorting;
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
