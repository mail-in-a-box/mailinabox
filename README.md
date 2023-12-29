# Unofficial Debian Mail-in-a-Box

=============

Simple porting of Mailinabox to Debian 12.
Original project: [https://github.com/mailinabox/mailinabox](https://github.com/mail-in-a-box/mailinabox)

## Version

Current version: v67.1.1-AiutoPcAmico
Upstream current implemented version: v67

## Changes implemented

- Compatibility with Debian 12.
- Updated php to version 8.2
- At the moment, OwnCloud is disabled, because it not supports php8.2
- Changed SMTP server sign
- more restrictive Fail2Ban configuration
- ask the user if he wants to disable the graylist

## Future implementation

- Changing the default index page more easily

## Installation guide

Please, open the file "INSTALL.md" for the complete guide to install Debian Mail-in-a-Box by AiutoPcAmico

## Changelogs

In this folder you can find 2 different changelog files:

- CHANGELOG.md is from the upstream project
- CHANGELOG_AiutoPcAmico.md relates to the changes made by AiutoPcAmico and strictly connected to the Debian porting
