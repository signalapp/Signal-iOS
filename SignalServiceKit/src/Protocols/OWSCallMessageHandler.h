//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class SSKProtoCallMessageAnswer;
@class SSKProtoCallMessageBusy;
@class SSKProtoCallMessageHangup;
@class SSKProtoCallMessageIceUpdate;
@class SSKProtoCallMessageOffer;
@class SignalServiceAddress;

@protocol OWSCallMessageHandler <NSObject>

- (void)receivedOffer:(SSKProtoCallMessageOffer *)offer
           fromCaller:(SignalServiceAddress *)caller NS_SWIFT_NAME(receivedOffer(_:from:));
- (void)receivedAnswer:(SSKProtoCallMessageAnswer *)answer
            fromCaller:(SignalServiceAddress *)caller NS_SWIFT_NAME(receivedAnswer(_:from:));
- (void)receivedIceUpdate:(SSKProtoCallMessageIceUpdate *)iceUpdate
               fromCaller:(SignalServiceAddress *)caller NS_SWIFT_NAME(receivedIceUpdate(_:from:));
- (void)receivedHangup:(SSKProtoCallMessageHangup *)hangup
            fromCaller:(SignalServiceAddress *)caller NS_SWIFT_NAME(receivedHangup(_:from:));
- (void)receivedBusy:(SSKProtoCallMessageBusy *)busy
          fromCaller:(SignalServiceAddress *)caller NS_SWIFT_NAME(receivedBusy(_:from:));

@end

NS_ASSUME_NONNULL_END
