mkdir storage

# mount volume

echo "CREATE TABLE users (email text, password text);" | sqlite3 /home/ubuntu/storage/mail.sqlite;

