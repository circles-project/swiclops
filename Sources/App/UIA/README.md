# Support for Matrix User-Interactive Auth (UIA)

The files in this folder add (very basic) support to Vapor for tracking
Matrix user-interactive auth (UIA) sessions.

Unlike Vapor's standard `Session`s, Matrix's UIA sessions do not use
cookies.  Instead, they rely on a special `session` string inside the
JSON request or response body.  Because the JSON request bodies can
be quite large, we cannot set UIA session id's in middleware like Vapor
normally does.  Instead, we need a way for the endpoint handlers, who
have the full request body, to connect with an existing session and
store/retrieve stuff there.
