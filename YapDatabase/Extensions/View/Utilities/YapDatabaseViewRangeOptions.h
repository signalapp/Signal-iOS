#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Range offsets are specified from either the beginning or end.
 *
 * @see fixedRangeWithLength:offset:from:
 * @see flexibleRangeWithStartingLength:startingOffset:from:
**/
typedef NS_ENUM(NSInteger, YapDatabaseViewPin) {
	YapDatabaseViewBeginning = 0, // index == 0
	YapDatabaseViewEnd       = 1, // index == last
};

/**
 * Grow options allow you to specify in which direction flexible ranges can grow.
 *
 * @see growOptions
**/
typedef NS_OPTIONS(NSUInteger, YapDatabaseViewGrowOptions) {
	YapDatabaseViewGrowPinSide    = 1 << 0,
	YapDatabaseViewGrowNonPinSide = 1 << 1,
	
	YapDatabaseViewGrowInRangeOnly = 0,
	YapDatabaseViewGrowOnBothSides = (YapDatabaseViewGrowPinSide | YapDatabaseViewGrowNonPinSide)	
};

/**
 * Range options allow you to specify a particular range of a group.
 *
 * For example, if a group contains thousands of items,
 * but you only want to display the most recent 50 items in your tableView,
 * then you can easily use range options to accomplish this.
 * 
 * YapDatabaseViewRangeOptions are plugged into YapDatabaseViewMappings.
 *
 * @see YapDatabaseViewMappings setRangeOptions:forGroup:
**/
@interface YapDatabaseViewRangeOptions : NSObject <NSCopying>

/**
 * There are 2 types of supported ranges: Fixed & Flexible
 * 
 * A fixed range is similar to using a LIMIT & OFFSET in a SQL query.
 * That is, it represents a designated range that doesn't change.
 * 
 * You create a fixed range by specifying a desired length
 * and an offset from either the beginning or end.
 * 
 * @param length
 *   The desired length of the range.
 *   The length doesn't need to be valid at this point in time.
 *   For example, if the group only has 4 items, you can still specify a length of 20 if that is the desired length.
 *   The mappings will automatically use a length of 4 to start, and automatically expand up to 20.
 * 
 * @param offset
 *   The offset from one either the beginning or end of the group.
 *   
 * @param beginningOrEnd
 *   Either YapDatabaseViewBeginning or YapDatabaseViewEnd.
 * 
 * Using YapDatabaseViewMappings along with a fixed range provides some unique features:
 *
 * - If you specify an offset from the end of the group (YapDatabaseViewEnd),
 *   you are essentially "pinning" the range to the end, and it will stay pinned that way regardless of
 *   inserted or deleted items elsewhere in the group.
 *   
 *   For example: If you pin the range to the end, with an offset of zero, and a length of 20,
 *   then the range will always specify the last 20 items in the group,
 *   even as the group length (as a whole) increases or decreases.
 * 
 * - The changeset processing will automatically create the proper row changes to match what you want.
 *   
 *   For example: You have a fixed range with length 20, pinned to the beginning with an offset of 0,
 *   and a new item is inserted at index 0. The changeset processing will automatically give you a row
 *   insert at index 0, and a row delete at the end of your range to properly account for the row
 *   that got pushed outside your range.
 * 
 *   Thus you get row animations for free, even when only displaying a subset.
 *   And all the math is already done for you.
**/
+ (nullable YapDatabaseViewRangeOptions *)fixedRangeWithLength:(NSUInteger)length
														offset:(NSUInteger)offset
														  from:(YapDatabaseViewPin)beginningOrEnd;

/**
 * There are 2 types of supported ranges: Fixed & Flexible
 * 
 * A flexible range is designed to grow and shrink.
 * To explain this concept, consider Apple's SMS Messages app:
 *   
 *   When you go into a conversation (tap on a persons name),
 *   the messages app starts by displaying the most recent 50 messages (with the most recent at bottom).
 *   Although there might be thousands of old messages between you and the other person,
 *   only 50 are in the view to begin with.
 *   As you send and/or receive messages within the view, the length will grow.
 *   And similarly, if you manually delete messages, the length will shrink.
 * 
 * Flexible ranges are designed to handle these types of user interfaces.
 * They're also quite customizeable to handle a number of different situations.
 * 
 * You create a flexible range by specifying an starting length
 * and an offset from either the beginning or end.
 *
 * @param length
 *   The desired starting length of the range.
 *   The length doesn't need to be valid at this point in time.
 *   For example, if the group only has 4 items, you can still specify a length of 20.
 *   The mappings will automatically correct the length as appropriate.
 *
 * @param offset
 *   The offset from one either the beginning or end of the group.
 *
 * @param beginningOrEnd
 *   Either YapDatabaseViewBeginning or YapDatabaseViewEnd.
 * 
 * Using YapDatabaseViewMappings along with a flexible range provides some unique features:
 *
 * - If you specify an offset from the end of the group (YapDatabaseViewEnd),
 *   you are essentially "pinning" the range to the end, and it will stay pinned that way regardless of
 *   inserted or deleted items elsewhere in the group.
 *
 *   For example: If you pin the range to the end, with an offset of zero,
 *   then the range length will grow as items are added to the end.
 *
 * - The changeset processing will automatically create the proper row changes to match what you want.
 *
 *   Thus you get row animations for free, even when only displaying a subset.
 *   And all the math is already done for you.
**/
+ (nullable YapDatabaseViewRangeOptions *)flexibleRangeWithLength:(NSUInteger)length
														   offset:(NSUInteger)offset
															 from:(YapDatabaseViewPin)beginningOrEnd;

/**
 * The current length of the range.
 *
 * When rangeOptions get plugged into mappings, the length is automatically updated to reflect the available length.
 * 
 * For a fixed range, the length will always be less than or equal to the original length.
 * For a flexible range, the length will grow and shrink as items get inserted and removed from the original range.
**/
@property (nonatomic, assign, readonly) NSUInteger length;

/**
 * The current offset of the range, relative to the pin (beginning or end of the group).
 * 
 * For a fixed range, the offset never changes.
 * For a flexible range, the offset will grow and shrink as items get inserted and removed between the range and pin.
**/
@property (nonatomic, assign, readonly) NSUInteger offset;

/**
 * The pin value represents the end from which the offset is calculated.
 * For example, assume a group contains 50 items and:
 * 
 * - length=10, offset=10, pin=YapDatabaseViewBeginning => the range is [10-19](inclusive) (10 back from 0)
 *
 * - length=10, offset=10, pin=YapDatabaseViewEnd => the range is [30-39](inclusive) (10 back from 49)
**/
@property (nonatomic, assign, readonly) YapDatabaseViewPin pin;

/**
 * There are 2 types of supported ranges: Fixed & Flexible
**/
@property (nonatomic, readonly) BOOL isFixedRange;
@property (nonatomic, readonly) BOOL isFlexibleRange;

/**
 * For FIXED ranges:
 * - the maxLength is readonly.
 * - it will always equal the length originally specified.
 *
 * For FLEXIBLE ranges:
 * - the maxLength allows you to specify a maximum length in which the range can grow.
 * 
 * In particular, if the range overflows the maxLength, then the changeset processing will automatically
 * trim items from the range (on the non-pin-side) to keep the range length within this maxLength.
 * 
 * For example, imagine you're displaying log entries in a tableView.
 * The range is pinned to the end, so as new log entries get appended to the database, they automatically get
 * inserted into the tableView. This allows the tableView to grow as the log grows. However, you don't want the
 * tableView growing too big, so you can set the maxLength in order to prevent this. That way, your tableView
 * grows as the logs come in (as expected). But if your tableView starts to get too big,
 * then the oldest log entries in the tableView start to fall off as new entries arrive.
 * This is eqivalent to switching from a flexible range to a fixed range,
 * but happens automatically without you having to write extra code to handle the edge case.
 * 
 * By default there is no maxLength, and thus the default maxLength is NSUIntegerMax.
**/
@property (nonatomic, readwrite) NSUInteger maxLength;

/**
 * For FIXED ranges:
 * - the minLength is readonly.
 * - it will always equal zero.
 *
 * For FLEXIBLE ranges:
 * - the minLength allows you to specify a minimum length that the range should keep (if possible).
 *
 * In particular, if the range underflows the minLength, then the changeset processing will automatically
 * adjust the offset or expand the range in order to keep entries in the view.
 * 
 * This is sometimes useful if items can get deleted from your range.
 * 
 * By default there is no minLength, and thus the default minLength is zero.
**/
@property (nonatomic, readwrite) NSUInteger minLength;

/**
 * GrowOptions ONLY apply to FLEXIBLE ranges.
 * 
 * The growOptions allow you to specify in which direction(s) the range may grow.
 * Let's look at a few concrete examples.
 * 
 * Example #1
 * 
 *   We're using a flexible range, with an offset of zero, pinned to the beginning.
 *   We're displaying news items, and the most recent items get inserted at index 0.
 *   The group currently contains thousands of items, and our range has a starting length of 50.
 *   If a new item gets inserted (at the beginning), we want it to get added to our range.
 *   So we would set our growOptions to be YapDatabaseViewGrowPinSide (this is the default value).
 * 
 * Example #2
 * 
 *   We're using a flexible range, with an offset of zero, pinned to the end.
 *   We're displaying log entries, with the most recent items getting appended to the end.
 *   The group currently contains thousands of items, and our range has a starting length of 50.
 *   If a new log item gets inserted (at the end), we want it to get added to our range.
 *   So we would set our growOptions to be YapDatabaseViewGrowPinSide (this is the default value).
 * 
 * Example #3
 * 
 *   We're making a UI that is somewhat akin to Facebook's news feed.
 *   That is, the most recent items come in at the top,
 *   but if you scroll to the bottom we automatically download older posts.
 *   However, we don't want to limit how far the user can scroll down.
 *   That is, if the user is bored, we're going to allow them to scroll down for
 *   however long we can fetch old items from the server.
 *   But obviously we can't allow the length of our tableView to grow infinitely long.
 *   So to accomplish this, we're going to use flexible ranges,
 *   and we're going to shift the length as the user scrolls down.
 *   To start with, we only have the 30 most recent posts in the database.
 *   And we set our flexible range as: length=30, offset=0, pin=YapDatabaseViewBeginning.
 *   Additionally we set our growOptions to: YapDatabaseViewGrowOnBothSides.
 *   Thus if we download new items, they'll get included in the range.
 *   And if we fetch older items, they'll also get included in the range.
 *   Now as the the user scrolls down, and we fetch more and more old items,
 *   we eventually get to the point were we shift the range.
 *   So when the range length gets to some max length that we want to support, we shift to a new flexible range:
 *   length=max, offset=0, pin=YapDatabaseViewEnd, growOptions=YapDatabaseViewGrowPinSide, maxLength=max
 *   This new range will keep the tableView length capped at max, and continually load older content as it gets fetched.
 *   To allow the user to scroll back up, we just increment the offset as the go.
 *   When they eventually get back up to the top, we reset the flexible range to its original value.
 * 
 *
 * To explain the different options, consider the following picture:
 * 
 *  - - - - -
 * | |x|x|x| |  <-- x marks the range
 *  - - - - -
 *  0 1 2 3 4
 *
 * groupCount = 5
 * flexibleRange: length=3, offset=1, pin=YapDatabaseViewBeginning, growOptions=YapDatabaseViewGrowPinSide
 * 
 * Now an item gets inserted at index 1 as follows:
 * 
 *  - - - - - -
 * | |?|x|x|x| |  <-- is ? added to the flexible range?
 *  - - - - - -
 *  0 1 2 3 4 5
 *
 * Does the item get added to the flexible range (with the given config options)?
 * The answer is YES.
 * 
 *  - - - - - -
 * | |x|x|x|x| |  <-- YES (based on pin & growOptions)
 *  - - - - - -
 *  0 1 2 3 4 5
 *
 * Because the flexible range is pinned to the beginning, and grows pin side.
 * So if anything gets inserted between what was originally at index 0, and what was originally at index 1,
 * then those items get added to the flexible range.
 * 
 * Notice that after the insert, the offset remains set at 1.
 * Notice that the answer would be NO if the flexible range was pinned to the end (with the same growOptions).
 * 
 * Now let's see what happens if something gets inserted at the end:
 * 
 *  - - - - - - -
 * | |x|x|x|x|?| |  <-- is ? added to the flexible range?
 *  - - - - - - -
 *  0 1 2 3 4 5 6
 * 
 * Does the item get added to the flexible range (with the given config options)?
 * The answer is NO.
 * 
 *  - - - - - - -
 * | |x|x|x|x| | |  <-- NO (based on pin & growOptions)
 *  - - - - - - -
 *  0 1 2 3 4 5 6
 * 
 * Because the flexible range is pinned to the beginning, and grows pin side.
 * 
 * Notice that after the insert, the offset remains set at 1.
 * Notice that the answer would be YES if the flexible range was pinned to the end (with the same growOptions).
 * 
 *  - - - - - - - -                 - - - - - - - -
 * |?| |x|x|x|x| | |  => NEVER =>  | | |x|x|x|x| | |
 *  - - - - - - - -                 - - - - - - - -
 *  0 1 2 3 4 5 6 7                 0 1 2 3 4 5 6 7
 * 
 *  - - - - - - - - -                  - - - - - - - - -
 * | | |x|?|x|x|x| | |  => ALWAYS =>  | | |x|x|x|x|x| | |
 *  - - - - - - - - -                  - - - - - - - - -
 *  0 1 2 3 4 5 6 7 8                  0 1 2 3 4 5 6 7 8
**/
@property (nonatomic, readwrite) YapDatabaseViewGrowOptions growOptions;

/**
 * Various copy options.
**/
- (id)copyWithNewLength:(NSUInteger)newLength;
- (id)copyWithNewOffset:(NSUInteger)newOffset;
- (id)copyWithNewLength:(NSUInteger)newLength newOffset:(NSUInteger)newOffset;

@end

NS_ASSUME_NONNULL_END
