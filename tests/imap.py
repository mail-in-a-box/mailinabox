import imaplib, os

M = imaplib.IMAP4_SSL(os.environ["INSTANCE_IP"])
M.login("testuser@testdomain.com", "testpw")
M.select()
print("Login successful.")
typ, data = M.search(None, 'ALL')
for num in data[0].split():
    typ, data = M.fetch(num, '(RFC822)')
    print('Message %s\n%s\n' % (num, data[0][1]))
M.close()
M.logout()

