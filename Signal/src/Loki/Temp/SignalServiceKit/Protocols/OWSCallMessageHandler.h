//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class SSKProtoCallMessageAnswer;
@class SSKProtoCallMessageBusy;
@class SSKProtoCallMessageHangup;
@class SSKProtoCallMessageIceUpdate;
@class SSKProtoCallMessageOffer;

@protocol OWSCallMessageHandler <NSObject>

- (void)receivedOffer:(SSKProtoCallMessageOffer *)offer
         fromCallerId:(NSString *)callerId NS_SWIFT_NAME(receivedOffer(_:from:));
- (void)receivedAnswer:(SSKProtoCallMessageAnswer *)answer
          fromCallerId:(NSString *)callerId NS_SWIFT_NAME(receivedAnswer(_:from:));
- (void)receivedIceUpdate:(SSKProtoCallMessageIceUpdate *)iceUpdate
             fromCallerId:(NSString *)callerId NS_SWIFT_NAME(receivedIceUpdate(_:from:));
- (void)receivedHangup:(SSKProtoCallMessageHangup *)hangup
          fromCallerId:(NSString *)callerId NS_SWIFT_NAME(receivedHangup(_:from:));
- (void)receivedBusy:(SSKProtoCallMessageBusy *)busy
        fromCallerId:(NSString *)callerId NS_SWIFT_NAME(receivedBusy(_:from:));

@end

NS_ASSUME_NONNULL_END
