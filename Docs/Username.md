#  Username

Swiclops provides a single UIA stage for claiming a username during registration.

This approach offers one major advantage over the standard (or "legacy") way of
handling usernames in the Matrix registration flow.

Normally, Matrix requires that the client provide the username in the body of the
`/register` request, starting with the first non-empty request in the UIA process.

However, that request body doesn't make its way to the code that actually processes
the `/register` request until *after* all of the user-interactive authentication
stages have been completed.  So therefore a client needs to first collect the
user's desired username, *then* deal with terms of service, registration tokens,
email verification, CAPTCHA's, and who knows what else.  Only after all that other
stuff has been completed can we finally tell the user if there was a problem with
their requested username.  For example, maybe some other user jumped in and registered
that name while we were waiting on our email verification to come through.  That's
not very user-friendly.  You might even call it rude.  A much better approach is
to handle one thing at a time.

To be fair, Matrix does provide another API endpoint to query whether a given 
username is still available.  But on the other hand, doing so is a huge privacy
leak.  I *don't want* to tell the whole world which usernames are available on
my server, because eventually that reveals which usernames are in use on my
server.  If a client hasn't passed some sort of gating function that tells me
they really are part of my server's community, then I don't want to tell them
**anything**.

Putting the username reservation step inside the UIA flow solves all of these
problems at once.

* A legitimate user gets immediate feedback when they request a username that they can't have

* Putting the username UIA stage after a gating stage like `m.login.registration_token`
  prevents random people on the internet from learning what account names are
  or are not registered on our server.

### `m.enroll.username`

Parameters:

`None`

Request:

```json
{
    ...
    "auth": {
        "session": "abcdwxyz",
        "type": "m.enroll.username",
        "username": "alice"
    }
}
```
