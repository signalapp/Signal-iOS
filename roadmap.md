# Roadmap: Integration of Peer Extra Public Key Fields

This document outlines the steps required to fully integrate the new `peerExtraPublicKey` and `peerExtraPublicKeyTimestamp` fields, recently added to the `ContactDetails` Protobuf message in `SignalService.proto`.

## Phase 1: Code Generation and Basic Model Updates

1.  **Prerequisites:**
    *   Ensure the Protocol Buffer compiler `protoc` (version 3.x or compatible) is installed and accessible in your system's PATH.
    *   Ensure the SwiftProtobuf plugin `protoc-gen-swift` is available. This is typically included with the `SwiftProtobuf` CocoaPod. The standard path relative to the project root is `Pods/SwiftProtobuf/Plugin/protoc-gen-swift`.

2.  **Regenerate Protobuf Swift Files:**
    *   Navigate to the project root directory in your terminal.
    *   Run the following command. (Note: If other `.proto` files like `StickerResources.proto` or `WebSocketResources.proto` also output to `SignalServiceKit/Protos/Generated/` and are typically generated together, include them in this command for consistency.)
        ```bash
        protoc --plugin=protoc-gen-swift=Pods/SwiftProtobuf/Plugin/protoc-gen-swift --swift_out=SignalServiceKit/Protos/Generated/ SignalService.proto Provisioning.proto
        ```

3.  **Verify Generated Code:**
    *   Open `SignalServiceKit/Protos/Generated/SignalService.pb.swift`.
    *   Locate the `ContactDetails` struct (or class).
    *   Confirm the presence of the new properties:
        *   `peerExtraPublicKey: Data?` (or equivalent for `optional bytes`)
        *   `peerExtraPublicKeyTimestamp: Int64?` (or equivalent for `optional int64`)
    *   Ensure no unintended changes have occurred in this file or `Provisioning.pb.swift`.

4.  **Update Internal Swift Data Models:**
    *   **SignalServiceKit Models:**
        *   Identify the primary Swift struct/class in `SignalServiceKit` used to represent a user's contact (e.g., `SignalAccount`, `Contact`, or similar).
        *   Add new optional properties to this model:
            ```swift
            var peerExtraPublicKey: Data?
            var peerExtraPublicKeyTimestamp: Int64? // Or Date? if timestamps are typically handled as Date objects internally
            ```
    *   **Signal App Models (if applicable):**
        *   If the main `Signal` application uses its own view models or data models for contacts that are distinct from `SignalServiceKit` models, update these as well to include the new fields.

## Phase 2: Logic and Storage Integration

5.  **Adapt Serialization/Deserialization Logic:**
    *   Locate the code responsible for converting between the internal Swift contact models (from Step 4) and the `SignalService.ContactDetails` Protobuf messages.
    *   **Serialization (Swift Model -> Protobuf):** When creating a `ContactDetails` message to be sent or stored, populate `peerExtraPublicKey` and `peerExtraPublicKeyTimestamp` from your internal model.
    *   **Deserialization (Protobuf -> Swift Model):** When a `ContactDetails` message is received (e.g., via sync, or loaded from storage), parse the new fields and update your internal Swift model.
    *   **Backward Compatibility:**
        *   Crucially, ensure all parsing logic gracefully handles the absence of these new fields. Since they are `optional` in the `.proto` definition, older clients will not send them. Your code must not crash or behave unexpectedly if these fields are `nil`.
        *   When sending to older clients (if identifiable, though generally not necessary for optional fields), these fields will simply be omitted if not set, or ignored by the older client if set.

6.  **Update Data Storage (Persistence Layer):**
    *   Identify where contact information (specifically the internal Swift models from Step 4) is stored (e.g., GRDB, CoreData).
    *   **Schema Migration (if necessary):**
        *   If using a database like GRDB or CoreData, you will likely need to add new columns to the contacts table to store `peerExtraPublicKey` (as `Data` or `BLOB`) and `peerExtraPublicKeyTimestamp` (as `Int64` or `Timestamp`).
        *   Implement a database migration to add these new columns. Ensure the migration handles existing rows gracefully (e.g., by setting a default value of `NULL` for the new columns in old records).
    *   **Update Data Access Objects (DAOs)/Repositories:**
        *   Modify the code that reads and writes contact data to include the new fields.

7.  **Update Contact Synchronization Logic:**
    *   Review how contact information is synced with the server and between linked devices (`SyncMessage.Contacts`, etc.).
    *   Ensure the new fields are included in the contact data being synced.
    *   Verify that devices receiving synced contact data correctly process and store these new fields.

8.  **Application Logic for New Fields:**
    *   Determine how these new fields will be used within the application. (This might be part of a larger feature not yet fully implemented).
    *   If these keys are to be used for any specific cryptographic purposes (e.g., new E2EE protocols, identity verification), implement that logic.
    *   If there's any UI component that needs to be aware of or react to the presence/absence or value of these fields (unlikely for raw keys/timestamps, but consider related metadata), make necessary UI updates.

## Phase 3: Testing and Validation

9.  **Unit Tests:**
    *   **Serialization/Deserialization:** Write tests to verify that `ContactDetails` messages are correctly serialized and deserialized with and without the new fields.
    *   **Data Storage:** Test that the new fields are correctly saved to and retrieved from the persistent store. Test database migrations if applicable.
    *   **Backward Compatibility:** Create test cases where `ContactDetails` messages are missing the new fields (simulating data from an older client) to ensure robust parsing.
    *   **Logic Tests:** Test any new application logic that uses these fields.

10. **Integration Tests:**
    *   Test the end-to-end flow of contact synchronization, ensuring the new fields propagate correctly between devices and the server.
    *   If these fields affect message encryption/decryption or other core functionalities, design integration tests for those scenarios.

11. **Manual Testing:**
    *   Perform thorough manual testing of all contact-related features:
        *   Adding/editing contacts.
        *   Linking new devices.
        *   Contact sync behavior.
        *   Profile sharing and updates.
    *   Test scenarios involving interaction between an updated client and an older client version (if possible in a test environment) to confirm backward compatibility.

## Phase 4: Documentation and Release

12. **Internal Documentation:**
    *   Update any internal technical documentation, diagrams, or developer guides that describe the contact data model or synchronization process to reflect the addition of these new fields.

13. **Release Considerations:**
    *   Monitor for any issues post-release, particularly around contact sync and data integrity.
    *   Be prepared for scenarios where users might have mixed versions of the app across their devices.
