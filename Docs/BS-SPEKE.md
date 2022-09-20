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


## Stages for Enrollment / Registration

### m.enroll.bsspeke-ecc.oprf

Initial Parameters

In the initial UIA response, the server provides the client with the list of
cryptographic primitives that it supports, namely the elliptic curve, the
hash function, and the parameters for the password hashing function.

```json
{
    ...
    "params": {
        ...
        "m.enroll.bsspeke-ecc.oprf": {
            "curve": "curve25519",
            "hash_function": "blake2b",
            "phf_params": {
                "name": "argon2i",
                "iterations": 3,
                "blocks": 100000
            }
        }
    }
}
```

Request

```json
{
    ...
    "auth": {
        "type": "m.enroll.bsspeke-ecc.oprf",
        "session": "abcdwxyz",
        "curve": "curve25519",
        "blind": "23256673567452234134635674567..."
    }
}
```


### m.enroll.bsspeke-ecc.save

Parameters

```json
{
    ...
    "params": {
        ...
        "m.enroll.bsspeke-ecc.save": {
            "blind_salt": "9087028349082348723659861239847019234..."  // base64-encoded curve point
        }
    }
}
```

Request

```json
{
    ...
    "auth": {
        "session": "abcdwxyz",
        "type": "m.enroll.bsspeke-ecc.enroll",
        "P": "987097565465465443873242343213435345...",  // base64-encoded client's base curve point
        "V": "023492349872350713450987345980723457...",  // base64-encoded client's public key
        "phf_params": {
            "name": "argon2i",
            "iterations": 3,
            "blocks": 100000
        }
    }
}
```

## Stages for Login / Authentication

### m.login.bsspeke-ecc.oprf

Parameters

```json
{
    ...
    "params": {
        ...
        "m.login.bsspeke-ecc.oprf": {
            "curve": "curve25519",
            "hash_function": "blake2b",
            "phf_params": {
                "name": "argon2i",
                "iterations": 3,
                "blocks": 100000
            }
        }
    }
}
```

Request

```json
{
    ...
    "auth": {
        "type": "m.enroll.bsspeke-ecc.oprf",
        "session": "abcdwxyz",
        "curve": "curve25519",
        "blind": "23256673567452234134635674567..."  // base64-encoded curve point
    }
}
```

### m.login.bsspeke-ecc.verify

Parameters

```json
{
    ...
    "params": {
        ...
        "m.login.bsspeke-ecc.verify": {
            "blind_salt": "9087028349082348723659861239847019234...",  // base64-encoded curve point
            "B": "87568346582639014018349823759824374..."              // base64-encoded server's ephemeral public key
        }
    }
}
```

Request

```json
{
    ...
    "auth": {
        "session": "abcdwxyz",
        "type": "m.enroll.bsspeke-ecc.enroll",
        "A": "213423436457546745686875678523123113...",        // base64-encoded client's ephemeral public key
        "verifier": "32434534574562341232312415456789789...",  // base64-encoded client verifier
        "phf_params": {
            "name": "argon2i",
            "iterations": 3,
            "blocks": 100000
        }
    }
}
```
