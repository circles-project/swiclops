# Swiclops Password auth module

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
