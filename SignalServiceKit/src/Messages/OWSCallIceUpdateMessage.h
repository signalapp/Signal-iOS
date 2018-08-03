//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class SSKProtoCallMessageIceUpdate;

/**
 * Sent by both parties out of band of the RTC calling channels, as part of setting up those channels. The messages
 * include network accessability information from the perspective of each client. Once compatible ICEUpdates have been
 * exchanged, the clients can connect directly.
 */
@interface OWSCallIceUpdateMessage : NSObject

- (instancetype)initWithCallId:(UInt64)callId
                           sdp:(NSString *)sdp
                 sdpMLineIndex:(SInt32)sdpMLineIndex
                        sdpMid:(nullable NSString *)sdpMid;

@property (nonatomic, readonly) UInt64 callId;
@property (nonatomic, readonly, copy) NSString *sdp;
@property (nonatomic, readonly) SInt32 sdpMLineIndex;
@property (nullable, nonatomic, readonly, copy) NSString *sdpMid;

- (nullable SSKProtoCallMessageIceUpdate *)asProtobuf;

@end

NS_ASSUME_NONNULL_END
