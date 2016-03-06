#import "YapActionItem.h"
#import "YapActionItemPrivate.h"

#import "NSDate+YapDatabase.h"


@implementation YapActionItem

@synthesize identifier = identifier;
@synthesize date = date;
@synthesize retryTimeout = retryTimeout;
@synthesize requiresInternet = requiresInternet;
@synthesize queue = queue;
@synthesize block = block;

@synthesize isStarted = isStarted;
@synthesize isPendingInternet = isPendingInternet;
@synthesize nextRetry = nextRetry;

- (instancetype)initWithIdentifier:(NSString *)inIdentifier
                              date:(NSDate *)inDate
                      retryTimeout:(NSTimeInterval)inRetryTimeout
                  requiresInternet:(BOOL)inRequiresInternet
                             block:(YapActionItemBlock)inBlock
{
	return [self initWithIdentifier:inIdentifier
	                           date:inDate
	                   retryTimeout:inRetryTimeout
	               requiresInternet:inRequiresInternet
	                          queue:nil
	                           block:inBlock];
}

- (instancetype)initWithIdentifier:(NSString *)inIdentifier
                              date:(nullable NSDate *)inDate
                      retryTimeout:(NSTimeInterval)inRetryTimeout
                  requiresInternet:(BOOL)inRequiresInternet
                             queue:(nullable dispatch_queue_t)inQueue
                             block:(YapActionItemBlock)inBlock
{
	NSAssert(inIdentifier != nil, @"YapActionItem: %@ - identifier cannot be nil !", NSStringFromSelector(_cmd));
	
	if ((self = [super init]))
	{
		identifier = [inIdentifier copy];
		date = inDate ? inDate : [NSDate dateWithTimeIntervalSinceReferenceDate:0.0];
		retryTimeout = inRetryTimeout;
		requiresInternet = inRequiresInternet;
		queue = inQueue;
		block = inBlock;
	}
	return self;
}

- (id)copyWithZone:(NSZone *)zone
{
	YapActionItem *copy = [[[self class] alloc] init];
	copy->identifier = identifier;
	copy->date = date;
	copy->retryTimeout = retryTimeout;
	copy->requiresInternet = requiresInternet;
	copy->queue = queue;
	copy->block = block;
	
	copy->isStarted = isStarted;
	copy->isPendingInternet = isPendingInternet;
	copy->nextRetry = nextRetry;
	
	return copy;
}

/**
 * Compares self.date with the atDate parameter.
 *
 * @param atDate
 *   The date to compare with.
 *   If nil, the current date is automatically used.
 *
 * @return
 *   Returns NO if self.date is after atDate (comparitively in the future).
 *   Returns YES otherwise (comparitively in the past or present).
**/
- (BOOL)isReadyToStartAtDate:(NSDate *)atDate
{
	if (atDate == nil)
		atDate = [NSDate date];
	
	// if (date <= atDate) -> date is in past   -> ready
	// if (date  > atDate) -> date is in future -> not ready
	//
	return [date isBeforeOrEqual:atDate];
}

/**
 * Compares self.nextRetry with the atDate parameter.
 *
 * @param atDate
 *   The date to compare with.
 *   If nil, the current date is automatically used.
 *
 * @return
 *   Returns NO if self.nextRetry is after atDate (comparitively in the future).
 *   Returns YES otherwise (comparitively in the past or present).
**/
- (BOOL)isReadyToRetryAtDate:(NSDate *)atDate
{
	if (nextRetry == nil)
	{
		return NO;
	}
	else
	{
		if (atDate == nil)
			atDate = [NSDate date];
		
		// if (nextRetry <= atDate) -> nextRetry is in past   -> ready
		// if (nextRetry  > atDate) -> nextRetry is in future -> not ready
		//
		return [nextRetry isBeforeOrEqual:atDate];
	}
}

- (BOOL)hasSameIdentifierAndDate:(YapActionItem *)another
{
	if (![identifier isEqualToString:another->identifier]) return NO;
	
	return [date isEqualToDate:another->date];
}

/**
 * Used for sorting items based on their date.
 * If two items have the exact same date, the comparison will fallback to comparing identifiers.
**/
- (NSComparisonResult)compare:(YapActionItem *)another
{
	NSAssert(another != nil, @"Attempting to compare with nil !");
	
	NSComparisonResult result = [date compare:another->date];
	
	if (result != NSOrderedSame)
		return result;
	else
		return [identifier compare:another->identifier options:NSLiteralSearch];
}

- (NSString *)description
{
	NSLocale *currentLocale = [NSLocale currentLocale];
	
	return [NSString stringWithFormat:
	  @"<YapActionItem: identifier(%@) date(%@) retryTimeout(%.0f) requiresInternet(%@)"
	                 @" isStarted(%@) isPendingInternet(%@) nextRetry(%@)>",
	  identifier,
	  [date descriptionWithLocale:currentLocale],
	  retryTimeout,
	  (requiresInternet ? @"YES" : @"NO"),
	  (isStarted ? @"YES" : @"NO"),
	  (isPendingInternet ? @"YES" : @"NO"),
	  [nextRetry descriptionWithLocale:currentLocale]];
}

@end
