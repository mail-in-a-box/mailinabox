from time import sleep
import requests
import os
import pytest

from settings import *


def test_web_hosting_http():
    """web hosting is redirecting to https"""
    url = 'http://' + TEST_DOMAIN
    r = requests.get(url, verify=False)

    # We should be redirected to https
    assert r.history[0].status_code == 301
    assert r.url == url.replace("http", "https") + "/"

    assert r.status_code == 200
    assert "this is a mail-in-a-box" in r.content
    
    
def test_admin_http():
    """Admin page is redirecting to https"""
    url = 'http://' + TEST_DOMAIN + "/admin"
    r = requests.get(url, verify=False)

    # We should be redirected to https
    assert r.history[0].status_code == 301
    assert r.url == url.replace("http", "https")

    assert r.status_code == 200
    assert "Log in here for your Mail-in-a-Box control panel" in r.content
    

def test_webmail_http():
    """Webmail is redirecting to https and displaying login page"""
    url = 'http://' + TEST_DOMAIN + "/mail"
    r = requests.get(url, verify=False)

    # We should be redirected to https
    assert r.history[0].status_code == 301
    assert r.url == url.replace("http", "https") + "/"

    # 200 - We should be at the login page
    assert r.status_code == 200
    assert 'Welcome to ' + TEST_DOMAIN + ' Webmail' in r.content


def test_owncloud_http():
    """ownCloud is redirecting to https and displaying login page"""
    url = 'http://' + TEST_DOMAIN + '/cloud'
    r = requests.get(url, verify=False)

    # We should be redirected to https
    assert r.history[0].status_code == 301
    assert r.url == url.replace("http", "https") + "/index.php/login"

    # 200 - We should be at the login page
    assert r.status_code == 200
    assert 'ownCloud' in r.content
