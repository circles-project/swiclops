# pytest tests for Swiclops

import requests

from typing import Optional


server_baseurl = 'http://127.0.0.1:8080'
login_path = '/_matrix/client/r0/login'
uia_headers = {"Content-Type": "application/json"}

def uia_validate_response(json: dict):
  assert "session" in json
  session_id = json["session"]
  #assert is_instance(str, session_id)
  assert type(session_id) == str

  assert "flows" in json
  flows = json["flows"]
  assert type(flows) == list

  for flow in flows:
    print("Flow:", flow)
    assert type(flow) == dict
    assert "stages" in flow
    for stage in flow["stages"]:
      assert type(stage) == str


def uia_login_get_new_session():
  response = requests.post(server_baseurl + login_path, headers=uia_headers, json={})

  assert response.status_code == 401
  json = response.json()

  uia_validate_response(json)
  
  session_id = json["session"]
  assert type(session_id) == str

  params = json["params"]
  assert type(params) == dict

  print("Got a new UIA session with session id =", session_id)
  print("New session has parameters for:", params.keys)

  return (session_id, params)

def uia_login_get_new_session_id():
  session_id, params = uia_login_get_new_session()
  return session_id


def uia_login_do_dummy_stage(session_id: str):
  print("Doing UIA dummy auth with session", session_id)
  request_json = {}
  request_json["auth"] = {"type": "m.login.dummy", "session": session_id}
  response = requests.post(server_baseurl + login_path, headers=uia_headers, json=request_json)

  assert response.status_code == 401
  response_json = response.json()

  uia_validate_response(response_json)
  
  assert session_id == response_json["session"]


def uia_login_do_foo_stage(session_id: str, foo: str):
  print("Doing UIA foo auth with session", session_id, "and foo", foo)
  request_json = {}
  request_json["auth"] = {"type": "m.login.foo", "session": session_id, "foo": foo}
  response = requests.post(server_baseurl + login_path, headers=uia_headers, json=request_json)
  assert response.status_code == 401


def test_login_uia_empty_post():
  session_id = uia_login_get_new_session_id()
  assert type(session_id) == str

def test_login_uia_foo():
  session_id, params = uia_login_get_new_session()
  assert type(session_id) == str

  print("Started new UIA session with id =", session_id)

  uia_login_do_dummy_stage(session_id)

  foo = params["m.login.foo"]["foo"]
  assert type(foo) == str

  uia_login_do_foo_stage(session_id, foo)

  assert False


