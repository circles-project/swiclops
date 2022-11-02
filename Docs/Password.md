# Swiclops Password auth module

The password module offers two stages: one for enrollment and one for authentication.

The enrollment module provides the server's minimum password strength requirements in
its UIA parameters.  Currently this is only a minimum length, but it could be extended
in the future to require some minimum number of numerals or special characters, or even
to require a certain password strength according to an algorithm like [zxcvbn](https://github.com/dropbox/zxcvbn).

## Enrollment / Registration

### m.enroll.password

Parameters

```json
{
    ...
    "params": {
        ...
        "m.enroll.password": {
            "minimum_length": 8
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
        "type": "m.enroll.password",
        "new_password": "hunter2"
    }
}
```

Response

| Status | Description |
| --- | --- |
| 200 | UIA complete, and the request was successful |
| 401 | UIA still in process |
| 403 | Password was rejected by policy |

## Login / Authentication

### m.login.password

Parameters
* None

Request

```json
{
    ...
    "auth": {
        "session": "abcdwxyz",
        "type": "m.login.password",
        "identifier": {
            "type": "m.id.user",
            "user": "@user:domain.tld"
        },
        "password": "hunter2"
    }
}
```

Response

| Status | Description |
| --- | --- |
| 200 | UIA complete, and the request was successful |
| 401 | UIA still in process |
| 403 | Password authentication failed |
