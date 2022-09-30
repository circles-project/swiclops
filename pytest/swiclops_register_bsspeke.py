#!/bin/env python3

import sys

import base64
import binascii
import json

import BSSpeke

import requests

import random

#domain = "example.com"
domain = sys.argv[1]
username = "test_%04x" % random.getrandbits(16)
user_id = "@%s:%s" % (username, domain)
print("Running test with user id [%s]" % user_id)
password = "P@ssword1"

client = BSSpeke.Client(user_id, domain, password)
client_id = client.get_client_id()
blind = client.generate_blind()
print("Got client_id = [%s]" % client_id)
print("Got blind = [%s]" % str(blind))

server = "https://matrix.%s" % domain
print("Got server = [%s]" % server)
path = "/_matrix/client/v3/register"

email = sys.argv[2]

url = server + path

headers = {
    'Content-Type': 'application/json',
    'Accept': 'application/json'
}


# Request 1: Empty #####################################################
print("\n\nRequest 1: New session\n")
r1 = requests.post(url, headers=headers, json={})
print("Got status: %d" % r1.status_code)
j1 = r1.json()
session_id = j1.get("session", None)
print("Got session id = [%s]" % session_id)
flows = j1.get("flows", None)
print("Got flows:")
uia_stages = None
for flow in flows:
    stages = flow.get("stages", [])
    print("\t", stages)
    if uia_stages is None:
        uia_stages = stages
print("Got response: ", json.dumps(j1, indent=4))

# Request 2: Registration token ########################################
print("\n\nRequest 2: Registration token\n")
body = {
    "username": username,
    "auth": {
        "type": "m.login.registration_token",
        "token": "0000-1111-2222-4444",
        "session": session_id
    }
}
r2 = requests.post(url, headers=headers, json=body)
print("Got status: %d" % r2.status_code)
j2 = r2.json()
completed = j2.get("completed", [])
print("Got completed stages: ", completed)
print("Got response: ", json.dumps(j2, indent=2))

# Request 3: Terms of service ##########################################
print("\n\nRequest 3: Terms of service\n")
body = {
    "username": username,
    "auth": {
        "type": "m.login.terms",
        "session": session_id
    }
}
r3 = requests.post(url, headers=headers, json=body)
print("Got status: %d" % r3.status_code)
j3 = r3.json()
completed = j3.get("completed", [])
print("Got completed stages: ", completed)
print("Got response: ", json.dumps(j3, indent=4))

require_email = True
if require_email:

    # Request 4: Request email token #######################################
    print("\n\nRequest 4: Request email token\n")
    body = {
        "username": username,
        "auth": {
            "type": "m.enroll.email.request_token",
            "email": email,
            "session": session_id
        }
    }
    r4 = requests.post(url, headers=headers, json=body)
    print("Got status: %d" % r4.status_code)
    completed = r4.json().get("completed", [])
    print("Got completed stages: ", completed)

    # Request 5: Submit email token #######################################
    email_token = input("Enter email token: ")
    print("\n\nRequest 5: Submit email token\n")
    body = {
        "username": username,
        "auth": {
            "type": "m.enroll.email.submit_token",
            "token": email_token,
            "session": session_id
        }
    }
    r5 = requests.post(url, headers=headers, json=body)
    print("Got status: %d" % r5.status_code)
    completed = r5.json().get("completed", [])
    print("Got completed stages: ", completed)

# Request 6: BS-SPEKE OPRF
print("\n\nRequest 6: BS-SPEKE OPRF\n")
oprf_params = j1["params"]["m.enroll.bsspeke-ecc.oprf"]
curve = oprf_params["curve"]
blind_base64 = binascii.b2a_base64(blind, newline=False).decode('utf-8')
print("Blind (base64) = [%s]" % blind_base64)

body = {
    "username": username,
    "auth": {
        "type": "m.enroll.bsspeke-ecc.oprf",
        "curve": curve,
        "blind": blind_base64,
        "session": session_id
    }
}
r6 = requests.post(url, headers=headers, json=body)
print("Got status: %d" % r6.status_code)
j6 = r6.json()
print("Got response: ", json.dumps(j6, indent=4))
completed = j6.get("completed", [])
print("Got completed stages: ", completed)
r6_params = j6.get("params", {})
print("Got params: ", json.dumps(r6_params))
if r6.status_code != 401:
    error = j6.get("error", "???")
    errcode = j6.get("errcode", "???")
    print("Got error response: %s %s" % (errcode, error))

# Request 7: BS-SPEKE Save 
print("\n\nRequest 7: BS-SPEKE OPRF\n")
save_params = j6["params"]["m.enroll.bsspeke-ecc.save"]
blind_salt = save_params["blind_salt"]
phf_params = {
    "name": "argon2i",
    "iterations": 3,
    "blocks": 100000
}
P,V = client.generate_P_and_V(base64.b64decode(blind_salt), phf_params)

body = {
    "username": username,
    "auth": {
        "type": "m.enroll.bsspeke-ecc.save",
        "P": binascii.b2a_base64(P, newline=False).decode('utf-8'),
        "V": binascii.b2a_base64(V, newline=False).decode('utf-8'),
        "phf_params": phf_params,
        "session": session_id
    }
}
r7 = requests.post(url, headers=headers, json=body)
print("Got status: %d" % r7.status_code)
j7 = r7.json()
completed = j7.get("completed", [])
print("Got completed stages: ", completed)
if r7.status_code != 200:
    error = j7.get("error", "???")
    errcode = j7.get("errcode", "???")
    print("Got error response: %s %s" % (errcode, error))


