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
{
	return [self initWithGroupingBlock:inGroupingBlock
	                 groupingBlockType:inGroupingBlockType
	                      sortingBlock:inSortingBlock
	                  sortingBlockType:inSortingBlockType
	                           version:0
	                           options:nil];
}

- (id)initWithGroupingBlock:(YapDatabaseViewGroupingBlock)inGroupingBlock
          groupingBlockType:(YapDatabaseViewBlockType)inGroupingBlockType
               sortingBlock:(YapDatabaseViewSortingBlock)inSortingBlock
           sortingBlockType:(YapDatabaseViewBlockType)inSortingBlockType
                    version:(int)inVersion
{
	return [self initWithGroupingBlock:inGroupingBlock
	                 groupingBlockType:inGroupingBlockType
	                      sortingBlock:inSortingBlock
	                  sortingBlockType:inSortingBlockType
	                           version:inVersion
	                           options:nil];
}

- (id)initWithGroupingBlock:(YapDatabaseViewGroupingBlock)inGroupingBlock
          groupingBlockType:(YapDatabaseViewBlockType)inGroupingBlockType
               sortingBlock:(YapDatabaseViewSortingBlock)inSortingBlock
           sortingBlockType:(YapDatabaseViewBlockType)inSortingBlockType
                    version:(int)inVersion
                    options:(YapDatabaseViewOptions *)inOptions
{
	// Todo: Throw exception
	return nil;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Instance
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@synthesize parentViewName = parentViewName;

@synthesize filteringBlock = filteringBlock;
@synthesize filteringBlockType = filteringBlockType;

@synthesize tag = tag;

- (id)initWithParentViewName:(NSString *)inParentViewName
              filteringBlock:(YapDatabaseViewFilteringBlock)inFilteringBlock
          filteringBlockType:(YapDatabaseViewBlockType)inFilteringBlockType
{
	return [self initWithParentViewName:inParentViewName
	                     filteringBlock:inFilteringBlock
	                 filteringBlockType:inFilteringBlockType
	                                tag:nil
	                            options:nil];
}

- (id)initWithParentViewName:(NSString *)inParentViewName
              filteringBlock:(YapDatabaseViewFilteringBlock)inFilteringBlock
          filteringBlockType:(YapDatabaseViewBlockType)inFilteringBlockType
                         tag:(NSString *)inTag
{
	return [self initWithParentViewName:inParentViewName
	                     filteringBlock:inFilteringBlock
	                 filteringBlockType:inFilteringBlockType
	                                tag:inTag
	                            options:nil];
}

- (id)initWithParentViewName:(NSString *)inParentViewName
              filteringBlock:(YapDatabaseViewFilteringBlock)inFilteringBlock
          filteringBlockType:(YapDatabaseViewBlockType)inFilteringBlockType
                         tag:(NSString *)inTag
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
		
		version = 0; // version isn't used
		
		if (inTag)
			tag = [inTag copy];
		else
			tag = @"";
		
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
