#import "YapDatabaseFilteredView.h"
#import "YapDatabaseFilteredViewConnection.h"
#import "YapDatabaseFilteredViewTransaction.h"

#import "YapDatabaseViewPrivate.h"


@interface YapDatabaseFilteredView () {
@public
	
	NSString *parentViewName;
	
	YapDatabaseViewFilteringBlock filteringBlock;
	YapDatabaseViewBlockType filteringBlockType;
}

@end

@protocol YapDatabaseFilteredViewDependency <NSObject>
@optional

- (void)viewDidRepopulate:(NSString *)registeredName;

@end
