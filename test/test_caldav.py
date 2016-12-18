import pytest
import caldav
from time import sleep

from settings import *
from common import random_id


def connect():
    url = "https://" + TEST_DOMAIN + "/cloud/remote.php/dav/calendars/" + TEST_ADDRESS + "/personal/"
    client = caldav.DAVClient(url, username=TEST_ADDRESS, password=TEST_PASSWORD, ssl_verify_cert=False)
    principal = client.principal()
    calendars = principal.calendars()
    return client, calendars[0]


vcal = """BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Example Corp.//CalDAV Client//EN
BEGIN:VEVENT
UID:{}
DTSTAMP:20170510T182145Z
DTSTART:20170512T170000Z
DTEND:20170512T180000Z
SUMMARY: this is a sample event
END:VEVENT
END:VCALENDAR
"""


def create_event():
    uid = random_id()
    event = vcal.format(uid)
    return event, uid
    

def event_exists(uid):
    c, cal = connect()
    try:
        event = cal.event(uid)
        return True
    except caldav.lib.error.NotFoundError:
        return False


def test_addremove_event():
    c, cal = connect()
    event, uid = create_event()
    cal.add_event(event)
    assert event_exists(uid)
    
    # now delete the event again 
    event = cal.event(uid)
    event.delete()
    sleep(3)
    assert (not event_exists(uid))
    

#def test_addremove_calendar():
#    c, cal = connect()
#    cal_id = random_id()
#    #c.principal().make_calendar(name="test", cal_id=cal_id)
#    cal = caldav.Calendar(c, name="TEST", parent=c.principal(), id="12").save()

    
        
