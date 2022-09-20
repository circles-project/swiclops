# Email Stages

The Swiclops UIA stages provide a simple, self-contained alternative to the
messy and often confusing mix of email API endpoints in the official Matrix
client-server spec.

The email auth checker module provides a total of four UIA stages for email:

* Two stages (request token and submit token) for enrolling a new user or 
  adding a new email address

* Two stages (request token and submit token) for authenticating an existing
  user via an email token


## Stages for Enrollment / Registration

### m.enroll.email.request\_token

Request

```json
{
    ...
    "auth": {
        "session": "abcdwxyz",
        "type": "m.enroll.email.request_token",
        "email": "user@domain.tld"
    }
}
```

### m.enroll.email.submit\_token

Request

```json
{
    ...
    "auth": {
        "session": "abcdwxyz",
        "type": "m.enroll.email.submit_token",
        "token": "987654"
    }
}
```

## Stages for Login / Authentication

### m.login.email.request\_token

Parameters

```json
{
    ...
    "params": {
        ...
        "m.login.email.request_token": {
            "addresses": ["address1@example.com", "address2@example.org", "example3@example.net"]
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
        "type": "m.login.email.request_token",
        "email": "user@domain.tld"
    }
}
```

### m.login.email.submit\_token

Request

```json
{
    ...
    "auth": {
        "session": "abcdwxyz",
        "type": "m.login.email.submit_token",
        "token": "123456"
    }
}
```
