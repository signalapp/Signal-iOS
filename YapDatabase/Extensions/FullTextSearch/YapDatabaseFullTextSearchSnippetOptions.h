#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * This class represents options that may be passed to the FTS snippet function.
 *
 * It correlates with the snippet funtion arguments as defined in sqlite's FTS module:
 * http://www.sqlite.org/fts3.html#section_4_2
 * 
 * For example, if you were searching for the word "favorite",
 * then a returned snippet may look something like this:
 * 
 * <b>...</b>one of my <b>favorite</b> cheese pairings is<b>...</b>
**/
@interface YapDatabaseFullTextSearchSnippetOptions : NSObject <NSCopying>


+ (NSString *)defaultStartMatchText; // @"<b>"
+ (NSString *)defaultEndMatchText;   // @"</b>"
+ (NSString *)defaultEllipsesText;   // @"..."

+ (int)defaultNumberOfTokens;        // 15

- (id)init;

/**
 * The startMatchText is inserted before matched terms/phrases, and also before injected ellipses text.
 * It is used to mark the beginning of special text within the snippet.
 *
 * If not set, it will be the defaultStartMatchText: @"<b>"
 *
 * @see defaultStartMatchText
**/
@property (nonatomic, copy) NSString *startMatchText;

/**
 * The endMatchText is inserted after matched terms/phrases, and also after injected ellipses text.
 * It is used to mark the end of special text within the snippet.
 *
 * If not set, it will be the defaultEndMatchText: @"</b>"
 *
 * @see defaultEndMatchText
**/
@property (nonatomic, copy) NSString *endMatchText;

/**
 * If the full text from the column is too big, the snippets will be a small subsection of the snippet,
 * centered on matching terms/phrases. When this occurs, and the snippet is truncated on the left and/or right,
 * then the ellipsesText will be inserted on the left and/or right.
 *
 * If not set, it will be the defaultEllipsesText: @"…"
 *
 * @see defaultEllipsesText
 * @see numberOfTokens
**/
@property (nonatomic, copy) NSString *ellipsesText;

/**
 * The column name from which to extract the returned fragments of text from.
 * If nil, then the text may be extracted from any column.
 * 
 * If not set, the default value is nil.
**/
@property (nonatomic, copy, nullable) NSString *columnName;

/**
 * The numberOfTokens is used as the (approximate) number of tokens to include in the returned snippet text value.
 *
 * If not set, it will be defaultNumberOfTokens: 15
 *
 * Setting this to a value of zero resets the value to the default.
 * Negative values are allowed, as the snippet function automatically uses the absolute value.
 * 
 * The maximum allowable absolute value is 64.
 *
 * @see defaultNumberOfTokens
**/
@property (nonatomic, assign) int numberOfTokens;

@end

NS_ASSUME_NONNULL_END
