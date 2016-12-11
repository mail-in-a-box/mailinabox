import socket

TEST_SERVER = '127.0.0.1'
TEST_DOMAIN = 'mailinabox.lan'
TEST_PORT = 2222
TEST_PASSWORD = '1234'
TEST_USER = 'me'
TEST_ADDRESS = TEST_USER + '@' + TEST_DOMAIN
TEST_SENDER = "someone@example.com"

socket.setdefaulttimeout(5)
