import pytest
from pycarddav import carddav

from settings import *


test_vcf = """
BEGIN:VCARD
VERSION:3.0
EMAIL;TYPE=PREF:foo@example.com
N:John Doe;;;;
FN:John Doe
REV:2012-08-02T21:16:14+00:00
PRODID:-//ownCloud//NONSGML Contacts 0.2//EN
UID:c292c7212b
END:VCARD
"""

def connect():
    url = "https://" + TEST_DOMAIN + "/cloud/remote.php/carddav/addressbooks/" + TEST_ADDRESS + "/contacts/"
    return carddav.PyCardDAV(url, user=TEST_ADDRESS, passwd=TEST_PASSWORD, verify=False, write_support=True)


def test_adddelete_contact():
    c = connect()
    abook = c.get_abook()
    prev_len = len(abook)

    url, etag = c.upload_new_card(test_vcf)
    abook = c.get_abook()
    assert len(abook) == prev_len + 1

    c.delete_vcard(url, etag)
    abook = c.get_abook()
    assert len(abook) == prev_len


def test_update_contact():
    c = connect()
    url, etag = c.upload_new_card(test_vcf)

    card = c.get_vcard(url)
    new_card = card.replace("John Doe", "Jane Doe")
    c.update_vcard(new_card, url, etag)

    card = c.get_vcard(url)
    assert "John Doe" not in card
    assert "Jane Doe" in card
