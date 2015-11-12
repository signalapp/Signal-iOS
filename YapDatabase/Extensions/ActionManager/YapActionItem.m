#import "YapActionItem.h"
#import "YapActionItemPrivate.h"

#import "NSDate+YapDatabase.h"


@implementation YapActionItem

@synthesize identifier = identifier;
@synthesize date = date;
@synthesize retryTimeout = retryTimeout;
@synthesize requiresInternet = requiresInternet;
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
	NSAssert(inIdentifier != nil, @"YapActionItem: %@ - identifier cannot be nil !", NSStringFromSelector(_cmd));
	
	if ((self = [super init]))
	{
		identifier = [inIdentifier copy];
		date = inDate ? inDate : [NSDate dateWithTimeIntervalSinceReferenceDate:0.0];
		retryTimeout = inRetryTimeout;
		requiresInternet = inRequiresInternet;
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
	copy->block = block;
	
	copy->isStarted = isStarted;
	copy->isPendingInternet = isPendingInternet;
	copy->nextRetry = nextRetry;
	
	return copy;
}

- (BOOL)isReadyToStartAtDate:(NSDate *)atDate
{
	if (atDate == nil)
		atDate = [NSDate date];
	
	return [date isAfterOrEqual:atDate];
}

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
		
		return [nextRetry isAfterOrEqual:atDate];
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
