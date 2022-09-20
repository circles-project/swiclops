# BS-SPEKE

[BS-SPEKE](https://gist.github.com/Sc00bz/e99e48a6008eef10a59d5ec7b4d87af3) is a
password-authenticated key exchange (PAKE) protocol from [Steve Thomas](https://tobtu.com/blog/2021/10/srp-is-now-deprecated/).

PAKE protocols are nice because the user experience is very familiar -- users
only need to remember their username and password.  And at the same time, a
PAKE provides better security than standard password login because the user's
password is never exposed to the server or on the network.

The BS-SPEKE module provides a total of four UIA stages:

* Two stages (OPRF and verify) to enroll a new user for BS-SPEKE
  authentication.  The same two stages can also be used to change
  the password for an existing user.

* Two stages (OPRF and verify) to authenticate a user who is already enrolled

## Initial Parameters

In the initial UIA response, the server provides the client with the list of
cryptographic primitives that it supports, namely the elliptic curve, the
hash function, and the parameters for the password hashing function.

For example:

```json
{
    "curve": "curve25519",
    "hash_function": "blake2b",
    "phf_params": {
        "name": "argon2i",
        "iterations": 3,
        "blocks": 100000
    }
}
```

## Stages for Enrollment / Registration

### m.enroll.bsspeke-ecc.oprf

### m.enroll.bsspeke-ecc.verify

## Stages for Login / Authentication

### m.login.bsspeke-ecc.oprf

### m.login.bsspeke-ecc.verify

