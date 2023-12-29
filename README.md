# Mail-in-a-Box

=============

Simple (I hope!) porting of Mailinabox to Debian 12.
Original project: [https://github.com/mailinabox/mailinabox](https://github.com/mail-in-a-box/mailinabox)
Upstream current implemented version: *v67* (v67-AiutoPcAmico)

## Changes implemented

- Compatibility with Debian 12.
- At the moment, OwnCloud is disabled, because it not supports php8.2
- Updated php to version 8.2
- Changed SMTP server sign
- more restrictive Fail2Ban configuration
- ask the user if he wants to disable the graylist

## Future implementation

- Changing the default index page more easily
