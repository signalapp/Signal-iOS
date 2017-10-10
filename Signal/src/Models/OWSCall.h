//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

//@class TSCall;
//@class TSInteraction;
//
// typedef enum : NSUInteger {
//    kCallOutgoing = 1,
//    kCallIncoming = 2,
//    kCallMissed = 3,
//    kCallOutgoingIncomplete = 4,
//    kCallIncomingIncomplete = 5,
//    // kGroupUpdateJoin = 6, has been deprecated.
//    // kGroupUpdateLeft = 7, has been deprecated.
//    // kGroupUpdate = 8, has been deprecated.
//    kCallMissedBecauseOfChangedIdentity = 9,
//} CallStatus;
//
//@interface OWSCall : NSObject <OWSMessageData>
//
//#pragma mark - Initialization
//
//- (instancetype)initWithCallRecord:(TSCall *)callRecord;
//- (instancetype)init NS_UNAVAILABLE;
//
///*
// * Returns the string Id of the user who initiated the call
// */
//@property (copy, nonatomic, readonly) NSString *senderId;
//
///*
// * Returns the display name for user who initiated the call
// */
//@property (copy, nonatomic, readonly) NSString *senderDisplayName;
//
///*
// * Returns date of the call
// */
//@property (copy, nonatomic, readonly) NSDate *date;
//
///*
// * Returns the call status
// * @see CallStatus
// */
//@property (nonatomic) CallStatus status;
//
///**
// *  String to be displayed
// */
//@property (nonatomic, copy) NSString *detailString;
//
//- (NSString *)dateText;
//
//@end

NS_ASSUME_NONNULL_END
