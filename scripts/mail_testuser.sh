# Create a test user: testuser@testdomain.com with password "testpw"
echo "INSERT INTO users (email, password) VALUES ('testuser@testdomain.com', '`sudo doveadm pw -s SHA512-CRYPT -p testpw`');" | sqlite3 storage/mail/users.sqlite

