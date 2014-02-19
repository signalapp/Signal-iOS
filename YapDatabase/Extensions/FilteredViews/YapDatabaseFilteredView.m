#import "YapDatabaseFilteredView.h"
#import "YapDatabaseFilteredViewPrivate.h"
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

+ (NSArray *)previousClassNames
{
	return @[ @"YapCollectionsDatabaseSecondaryIndex" ];
}

#pragma mark Invalid

- (id)initWithGroupingBlock:(YapDatabaseViewGroupingBlock)inGroupingBlock
          groupingBlockType:(YapDatabaseViewBlockType)inGroupingBlockType
               sortingBlock:(YapDatabaseViewSortingBlock)inSortingBlock
           sortingBlockType:(YapDatabaseViewBlockType)inSortingBlockType
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
#pragma mark Instance
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@synthesize parentViewName = parentViewName;

@synthesize filteringBlock = filteringBlock;
@synthesize filteringBlockType = filteringBlockType;

- (id)initWithParentViewName:(NSString *)inParentViewName
              filteringBlock:(YapDatabaseViewFilteringBlock)inFilteringBlock
          filteringBlockType:(YapDatabaseViewBlockType)inFilteringBlockType
{
	return [self initWithParentViewName:inParentViewName
	                     filteringBlock:inFilteringBlock
	                 filteringBlockType:inFilteringBlockType
	                         versionTag:nil
	                            options:nil];
}

- (id)initWithParentViewName:(NSString *)inParentViewName
              filteringBlock:(YapDatabaseViewFilteringBlock)inFilteringBlock
          filteringBlockType:(YapDatabaseViewBlockType)inFilteringBlockType
                  versionTag:(NSString *)inVersionTag
{
	return [self initWithParentViewName:inParentViewName
	                     filteringBlock:inFilteringBlock
	                 filteringBlockType:inFilteringBlockType
	                         versionTag:inVersionTag
	                            options:nil];
}

- (id)initWithParentViewName:(NSString *)inParentViewName
              filteringBlock:(YapDatabaseViewFilteringBlock)inFilteringBlock
          filteringBlockType:(YapDatabaseViewBlockType)inFilteringBlockType
                  versionTag:(NSString *)inVersionTag
                     options:(YapDatabaseViewOptions *)inOptions
{
	NSAssert(inParentViewName != nil, @"Invalid parentViewName");
	NSAssert(inFilteringBlock != NULL, @"Invalid filteringBlock");
	
	NSAssert(inFilteringBlockType == YapDatabaseViewBlockTypeWithKey ||
	         inFilteringBlockType == YapDatabaseViewBlockTypeWithObject ||
	         inFilteringBlockType == YapDatabaseViewBlockTypeWithMetadata ||
	         inFilteringBlockType == YapDatabaseViewBlockTypeWithRow,
	         @"Invalid filteringBlockType");
	
	if ((self = [super init]))
	{
		parentViewName = [inParentViewName copy];
		
		filteringBlock = inFilteringBlock;
		filteringBlockType = inFilteringBlockType;
		
		versionTag = inVersionTag ? [inVersionTag copy] : @"";
		
		options = inOptions ? [inOptions copy] : [[YapDatabaseViewOptions alloc] init];
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

@end
