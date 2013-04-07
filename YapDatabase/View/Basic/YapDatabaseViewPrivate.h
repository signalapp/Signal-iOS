#import <Foundation/Foundation.h>

#import "YapDatabaseView.h"
#import "YapDatabaseViewTransaction.h"

@interface YapDatabaseView () {
@public
	YapDatabaseViewFilterBlock filterBlock;
	YapDatabaseViewSortBlock sortBlock;
	
	YapDatabaseViewBlockType filterBlockType;
	YapDatabaseViewBlockType sortBlockType;
}

@end
