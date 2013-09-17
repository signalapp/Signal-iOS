#import <Foundation/Foundation.h>

/**
 * This class represents options that may be passed to the FTS snippet function.
 * 
**/
@interface YapDatabaseFullTextSearchSnippetOptions : NSObject <NSCopying>

@property (nonatomic, copy) NSString *startMatchText;
@property (nonatomic, copy) NSString *endMatchText;
@property (nonatomic, copy) NSString *ellipsesText;

@property (nonatomic, copy) NSString *columnName;

@property (nonatomic, assign) NSUInteger numberOfTokens;

@end
