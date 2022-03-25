# pytest tests for Swiclops

import requests

def test_login_uia():
  server_baseurl = 'http://127.0.0.1:8080'
  login_path = '/_matrix/client/r0/login'
  response = requests.post(server_baseurl + login_path, json={})

  assert response.status_code == 401
