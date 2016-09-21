//  Created by Dylan Bourgeois on 20/11/14.
//  Portions Copyright (c) 2016 Open Whisper Systems. All rights reserved.

#import "OWSCall.h"
#import <JSQMessagesViewController/JSQMessagesTimestampFormatter.h>
#import <JSQMessagesViewController/UIImage+JSQMessages.h>

@interface OWSCall ()

// -- Redeclaring properties from OWSMessageData protocol to synthesize variables
@property (nonatomic) TSMessageAdapterType messageType;
@property (nonatomic, getter=isExpiringMessage) BOOL expiringMessage;
@property (nonatomic) uint64_t expiresAtSeconds;
@property (nonatomic) uint32_t expiresInSeconds;

@end

@implementation OWSCall

#pragma mark - Initialzation

- (id)init
{
    NSAssert(NO,
        @"%s is not a valid initializer for %@. Use %@ instead",
        __PRETTY_FUNCTION__,
        [self class],
        NSStringFromSelector(@selector(initWithCallerId:callerDisplayName:date:status:displayString:)));
    return [self initWithCallerId:nil callerDisplayName:nil date:nil status:0 displayString:nil];
}

- (instancetype)initWithCallerId:(NSString *)senderId
               callerDisplayName:(NSString *)senderDisplayName
                            date:(NSDate *)date
                          status:(CallStatus)status
                   displayString:(NSString *)detailString
{
    NSParameterAssert(senderId != nil);
    NSParameterAssert(senderDisplayName != nil);

    self = [super init];
    if (!self) {
        return self;
    }

    _senderId = [senderId copy];
    _senderDisplayName = [senderDisplayName copy];
    _date = [date copy];
    _status = status;
    _expiringMessage = NO; // TODO - call notifications should expire too.
    _messageType = TSCallAdapter;

    // TODO interpret detailString from status. make sure it works for calls and
    // our re-use of calls as group update display
    _detailString = [detailString stringByAppendingFormat:@" "];

    return self;
}

- (NSString *)dateText
{
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    dateFormatter.timeStyle = NSDateFormatterShortStyle;
    dateFormatter.dateStyle = NSDateFormatterMediumStyle;
    dateFormatter.doesRelativeDateFormatting = YES;
    return [dateFormatter stringFromDate:_date];
}

#pragma mark - NSObject

- (BOOL)isEqual:(id)object
{
    if (self == object) {
        return YES;
    }

    if (![object isKindOfClass:[self class]]) {
        return NO;
    }

    OWSCall *aCall = (OWSCall *)object;

    return [self.senderId isEqualToString:aCall.senderId] &&
        [self.senderDisplayName isEqualToString:aCall.senderDisplayName]
        && ([self.date compare:aCall.date] == NSOrderedSame) && self.status == aCall.status;
}

- (NSUInteger)hash
{
    return self.senderId.hash ^ self.date.hash;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@: senderId=%@, senderDisplayName=%@, date=%@>",
                     [self class],
                     self.senderId,
                     self.senderDisplayName,
                     self.date];
}

#pragma mark - OWSMessageEditing

- (BOOL)canPerformEditingAction:(SEL)action
{
    return NO;
}

- (void)performEditingAction:(SEL)action
{
    // Shouldn't get here, as only supported actions should be exposed via canPerformEditingAction
    NSString *actionString = NSStringFromSelector(action);
    DDLogError(@"%@ '%@' action unsupported", self.tag, actionString);
}

#pragma mark - JSQMessageData

- (BOOL)isMediaMessage
{
    return NO;
}

#pragma mark - NSCoding

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    NSString *senderId = [aDecoder decodeObjectForKey:NSStringFromSelector(@selector(senderId))];
    NSString *senderDisplayName = [aDecoder decodeObjectForKey:NSStringFromSelector(@selector(senderDisplayName))];
    NSDate *date = [aDecoder decodeObjectForKey:NSStringFromSelector(@selector(date))];
    CallStatus status = (CallStatus)[aDecoder decodeIntegerForKey:NSStringFromSelector(@selector(status))];
    NSString *displayString = @""; // FIXME what should this be?

    return [self initWithCallerId:senderId
                callerDisplayName:senderDisplayName
                             date:date
                           status:status
                    displayString:displayString];
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:self.senderId forKey:NSStringFromSelector(@selector(senderId))];
    [aCoder encodeObject:self.senderDisplayName forKey:NSStringFromSelector(@selector(senderDisplayName))];
    [aCoder encodeObject:self.date forKey:NSStringFromSelector(@selector(date))];
    [aCoder encodeDouble:self.status forKey:NSStringFromSelector(@selector(status))];
}

#pragma mark - NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
    return [[[self class] allocWithZone:zone] initWithCallerId:self.senderId
                                             callerDisplayName:self.senderDisplayName
                                                          date:self.date
                                                        status:self.status
                                                 displayString:self.detailString];
}

- (NSUInteger)messageHash
{
    return self.hash;
}

- (NSString *)text
{
    return _detailString;
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end
