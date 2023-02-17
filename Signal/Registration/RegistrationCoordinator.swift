//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Manages the step-to-step state of primary device registration,
/// including re-registration and change number.
public protocol RegistrationCoordinator {

    /// Call this method to determine which step comes next in the flow.
    /// If nothing has changed, this may be the current step, in which case
    /// no change in the UI is needed.
    ///
    /// The idea is that view controllers should be (mostly) stateless, and rely on
    /// the coordinator to update its state when actions are taken, then get the next
    /// step to know what view to push next.
    func nextStep() -> Guarantee<RegistrationStep>

    /// Show the system permissions prompts, proceeding to the next step when done.
    ///
    /// If something goes wrong, the next step will be the same as the current step
    /// but which attached metadata giving more info on the rejection.
    func requestPermissions() -> Guarantee<RegistrationStep>

    /// Submit an e164 to use, returning the next step to take.
    /// If the e164 is rejected for any reason, the next step will be the same current step
    /// but with attached metadata giving more info on the rejection.
    ///
    /// An e164 may already be known (e.g. re-registration); this call cements that
    /// e164. Until this is called, the e164 will not actually be used for registration.
    /// This gives the user a chance to change it before any automatic steps are taken.
    func submitE164(_ e164: String) -> Guarantee<RegistrationStep>

    /// Request an SMS code be sent, returning the next step to take.
    /// If requesting a code is disallowed for any reason, the next step will be the same current
    /// step but with attached metadata giving more info on the reason.
    func requestSMSCode() -> Guarantee<RegistrationStep>

    /// Request an voice code be sent, returning the next step to take.
    /// If requesting a code is disallowed for any reason, the next step will be the same current
    /// step but with attached metadata giving more info on the reason.
    func requestVoiceCode() -> Guarantee<RegistrationStep>

    /// Submit a verification code, returning the next step to take.
    /// If the code is rejected for any reason, the next step will be the same current
    /// step but with attached metadata giving more info on the rejection.
    func submitVerificationCode(_ code: String) -> Guarantee<RegistrationStep>

    /// Submit a capcha token to fulfill the captcha challenge step and go to the next step.
    /// If the token is rejected for any reason, the next step will be the same current
    /// step but with attached metadata giving more info on the rejection.
    func submitCaptcha(_ token: String) -> Guarantee<RegistrationStep>

    /// Set the PIN code, whether that be for the first time, to fetch from KBS, or
    /// to confirm the code we already know about locally.
    /// If the code is rejected for any reason, the next step will be the same current
    /// step but with attached metadata giving more info on the rejection.
    func submitPINCode(_ code: String) -> Guarantee<RegistrationStep>

    /// Set whether the user's PNI should be discoverable by phone number.
    /// If the update is rejected for any reason, the next step will be the same current
    /// step but with attached metadata giving more info on the rejection.
    func setPhoneNumberDiscoverability(_ isDiscoverable: Bool) -> Guarantee<RegistrationStep>

    /// Set the user's profile information.
    /// If the update is rejected for any reason, the next step will be the same current
    /// step but with attached metadata giving more info on the rejection.
    func setProfileInfo(givenName: String, familyName: String?, avatarData: Data?) -> Guarantee<RegistrationStep>
}
