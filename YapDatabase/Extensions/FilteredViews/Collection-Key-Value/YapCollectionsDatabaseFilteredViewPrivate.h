#import "YapCollectionsDatabaseFilteredView.h"
#import "YapCollectionsDatabaseFilteredViewConnection.h"
#import "YapCollectionsDatabaseFilteredViewTransaction.h"

#import "YapCollectionsDatabaseViewPrivate.h"


@interface YapCollectionsDatabaseFilteredView () {
@public
	
	NSString *parentViewName;
	
	YapCollectionsDatabaseViewFilteringBlock filteringBlock;
	YapCollectionsDatabaseViewBlockType filteringBlockType;
	
	NSString *tag;
}

@end
