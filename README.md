# Swiclops - A Matrix user-interactive authentication (UIA) server

Swiclops handles authentication, registration, and other user management
tasks for a Matrix homeserver.

It can be configured to provide user-interactive authentication (UIA) on
the Matrix `/login` endpoint, similar to [MSC2835](https://github.com/Sorunome/matrix-doc/blob/soru/uia-on-login/proposals/2835-uia-on-login.md).
This opens up many exciting possibilities, including:
* Requiring acceptance of the latest terms of service in order to log in
* Multi-stage authentication protocols, such as WebAuthn or PassKeys, or
  various password-authenticated key exchange (PAKE) protocols
* Two-factor authentication

## Authentication Modules
* [MSC3231](https://github.com/matrix-org/matrix-spec-proposals/blob/main/proposals/3231-token-authenticated-registration.md) Registration Tokens
  - Invite your friends to join your server, without opening it to the whole world
* Token-based email validation
  - No link to click, simply enter the 6-digit code
  - More natural for non-browser applications
* Cryptographic login with [BS-SPEKE](https://gist.github.com/Sc00bz/e99e48a6008eef10a59d5ec7b4d87af3)
  - User experience is identical to legacy password auth
  - Server never learns the password, so it can also be used to derive secret keys
* Legacy password auth (`m.login.password`)
  - For compatibility with existing systems 
* Terms of service
  - Can require that users accept the latest terms in order to log in
* (Coming soon!) Support for paid subscriptions with the Apple App Store and Google Play Store
* (Coming soon!) Support for Apple FaceID and TouchID


## Prerequisites
Swiclops authenticates its requests to the Matrix homeserver using shared
secrets.
* Shared secret registration using the [Synapse admin API](https://matrix-org.github.io/synapse/latest/admin_api/register_api.html)
* Authentication for other requests using the [Devture shared secret auth](https://github.com/devture/matrix-synapse-shared-secret-auth) plugin

Currently Swiclops only supports using Synapse as its "backend" homeserver.
However, all that would be required to support other homeservers, such as
Dendrite or Conduit, would be for those homeservers to support the two
APIs listed above.

## Installation
The easiest way to install Swiclops is using Ansible and Docker.
We have created an Ansible role for it in a fork of the popular
[matrix-docker-ansible-deploy](https://github.com/cvwright/matrix-docker-ansible-deploy/tree/swiclops)
playbook.

## History
Once upon a time, there was a project called Syclops where we attempted
to create a UIA server by extracting the UIA code from the Matrix homeserver
[Synapse](https://github.com/matrix-org/synapse).
That effort lasted about a minute before colliding with reality.

Swiclops is another attempt at Syclops, written from scratch in Swift with Vapor.

An earlier project, [Midnight](https://github.com/KombuchaPrivacy/midnight), was
another predecessor to Swiclops.  Midnight provided an early version of registration
tokens and proxied all other UIA stages to the homeserver.
