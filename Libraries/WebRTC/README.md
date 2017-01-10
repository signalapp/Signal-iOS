The RTCAudioSession.h header isn't included in the standard build of
WebRTC, so we've vendored it here. Otherwise we're using the vanilla
framework.

We use the RTCAudioSession header to manually manage the RTC audio
session, so as to not start recording until the call is connected.

