This document outlines the main abstractions (layers) in the Session app. These layers should be as independent from eachother as possible.

# Service Node / File Server / Open Group Communication Layer

* Onion requests
* Service Node RPC calls
* Message sending & receiving (in a message agnostic manner, i.e. without any knowledge of what the message is)
* Swarm and Service Node management (e.g. error handling)
* File server API
* Open group API

# Session Protocol Layer

* Customized session handling protocol on top of Signal's implementation (i.e. session reset and things like that)
* Multi device protocol
* Customized closed groups protocol on top of Signal's implementation
* Customized profile management protocol on top of Signal's implementation
* Friend request protocol
* Customized sync messages protocol on top of Signal's implementation
* Customized transcripts, receipts & typing indicators protocol on top of Signal's implementation


# Signal Protocol Layer

Don't touch this. Ever.

# Push Notifications Layer

Only applicable to mobile. Speaks for itself.

# Database Layer

Built on top of Signal's implementation. Responsible for storing state used by the Session protocol layer and the communication layer.

# UI Layer

Should be as independent from Signal as possible. Ideally re-built from the ground up.
