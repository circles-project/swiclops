# Swiclops - A Matrix user-interactive authentication (UIA) server

Swiclops handles authentication, registration, and other user management
tasks for a Matrix homeserver.

## Features
* MSC3231 Registration Tokens
* Token-based email validation
* Cryptographic login with [BS-SPEKE](https://gist.github.com/Sc00bz/e99e48a6008eef10a59d5ec7b4d87af3)
* (Coming soon!) Support for paid subscriptions with the Apple App Store and Google Play Store

## Prerequisites
Swiclops authenticates its requests to the Matrix homeserver using shared
secrets.
* Shared secret registration using the [Synapse admin API](https://matrix-org.github.io/synapse/latest/admin_api/register_api.html)
* Authentication for other requests using the [Devture shared secret auth](https://github.com/devture/matrix-synapse-shared-secret-auth) plugin

Currently Swiclops only supports using Synapse as its "backend" homeserver.
However, all that would be required to support other homeservers, such as
Dendrite or Conduit, would be for those homeservers to support the two
APIs listed above.

## History
Once upon a time, there was a project called Syclops where we attempted
to create a UIA server by extracting the UIA code from
[Synapse](https://github.com/matrix-org/synapse).
That effort lasted about a minute before colliding with reality.

Swiclops is another attempt at Syclops, written from scratch in Swift with Vapor.

An earlier project, [Midnight](https://github.com/KombuchaPrivacy/midnight), was
another predecessor to Swiclops.  Midnight provided an early version of registration
tokens and proxied all other UIA stages to the homeserver.
