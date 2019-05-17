# Loki Session Reset

## Signal
Since Signal uses a centralised server, creating sessions is easy as the prekeys can be easily fetched.

The process is as follows:

1. `A` deletes all their sessions and sends `End Session` to `B`
    - `A` contacts the server and creates a new session
2. `B` Gets this message and deletes all sessions.
3. `B` Sends a message with a newly created session
    - `B` contacted server and established this
4. `A` and `B` now have the same sessions so they can delete any archived ones.

## Loki
Loki doesn't have a centralised server and thus we need to change the process above with something similar. 

We have to introduce a session reset state `sessionState` which can take the following states:
- `none`: No session reset is in progress
- `initiated`: We have initiated the session reset
- `received`: We have received a session reset from the other user

The new process is as follows:

1. `A` Sends `End Session` with a `PreKeyBundle` and archives its own session.
    - `sessionState = initiated`
    - The session is archived as we could get a message from `B` using the archived session, so we still want to be able to decrypt that.
    - We can show `Session reset in progress`
2. `B` Gets this message and saves the `PreKeyBundle` and archives its own sessions.
    - `sessionState = received`
    - `B` sends an empty message, which will trigger a new session to be created.
    - `B` deletes the `PreKeyBundle` once session is created.
    - We can show `Session reset in progress`
3. `A` and `B` both do the routine below when receiving messages.

### Upon receiving message (Only applies to PreKey and Cipher messages)

- Store the current active session `PS`
- Decrypt the message
    - Decrypting a message can cause the active session to change
- If `sessionState == none` then it means that we haven't started session reset and we can abort.
- Get the current session `CS`
- If `PS` is `nil` then abort as we didn't have a session before.
- If `CS != PS` then sessions were changed.
    - If `sessionState == received` then it means that the sender used an old session to contact us. We need to wait for them to use the new one.
        - Archive `CS` and set the session to `PS`
    - If `sessionState == initiated` then it means that the sender acknowledged our session reset and sent a message with a new session
        - Delete all session except `CS`
        - `sessionState = none`
        - Send an empty message to confirm session adoption
        - We can show `Session reset done`
- If `CS == PS` then sessions were the same.
    - If `sessionState == received` then it means that the new session we created is the one the sender used for sending message. We have successfully adopted the new session.
    - Delete all sessions except `PS`
    - `sessionState = none`
    - We can show `Session reset done`
