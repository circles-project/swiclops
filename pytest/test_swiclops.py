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


def uia_login_get_new_session_id():
  response = requests.post(server_baseurl + login_path, headers=uia_headers, json={})

  assert response.status_code == 401
  json = response.json()

  uia_validate_response(json)
  
  session_id = json["session"]

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



def test_login_uia_empty_post():
  session_id = uia_login_get_new_session_id()
  assert type(session_id) == str

def test_login_uia_password():
  session_id = uia_login_get_new_session_id()
  assert type(session_id) == str

  print("Started new UIA session with id =", session_id)

  uia_login_do_dummy_stage(session_id)

  assert False
