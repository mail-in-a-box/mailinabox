import pytest

from settings import *


def test_ssh_banner():
    """SSH is responding with its banner"""
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.connect((TEST_SERVER, TEST_PORT))
    data = s.recv(1024)
    s.close()

    assert data.startswith("SSH-2.0-OpenSSH")
