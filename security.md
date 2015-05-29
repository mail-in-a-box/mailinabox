Mail-in-a-Box Security Guide
============================

Mail-in-a-Box turns a fresh Ubuntu 14.04 LTS 64-bit machine into a mail server appliance by installing and configuring various components.

This page documents the security features of Mail-in-a-Box. The term “box” is used below to mean a configured Mail-in-a-Box.

Threat Model
------------

Nothing is perfectly secure, and an adversary with sufficient resources can always penetrate a system.

The primary goal of Mail-in-a-Box is to make deploying a good mail server easy, so we balance ― as everyone does ― privacy and security concerns with the practicality of actually deploying the system. That means we make certain assumptions about adversaries. We assume that adversaries . . .

* Do not have physical access to the box (i.e., we do not aim to protect the box from physical access).
* Have not been given Unix accounts on the box (i.e., we assume all users with shell access are trusted).

On the other hand, we do assume that adversaries are performing passive surveillance and, possibly, active man-in-the-middle attacks. And so:

* User credentials are always sent through SSH/TLS, never in the clear.
* Outbound mail is sent with the highest level of TLS possible (more on that below).

User Credentials
----------------

The box's administrator and its (non-administrative) mail users must sometimes communicate their credentials to the box.

### Services behind TLS

These services are protected by [TLS](https://en.wikipedia.org/wiki/Transport_Layer_Security):

* SMTP Submission (port 587). Mail users submit outbound mail through SMTP with STARTTLS on port 587.
* IMAP/POP (ports 993, 995). Mail users check for incoming mail through IMAP or POP over TLS.
* HTTPS (port 443). Webmail, the Echange/ActiveSync protocol, the administrative control panel, and any static hosted websites are accessed over HTTPS.

The services all follow these rules:

* SSL certificates are generated with 2048-bit RSA keys and SHA-256 fingerprints. The box provides a self-signed certificate by default. The [setup guide](https://mailinabox.email/guide.html) explains how to verify the certificate fingerprint on first login. Users are encouraged to replace the certificate with a proper CA-signed one. ([source](setup/ssl.sh))
* Only TLSv1, TLSv1.1 and TLSv1.2 are offered (the older SSL protocols are not offered).
* Export-grade ciphers, the anonymous DH/ECDH algorithms (aNULL), and clear-text ciphers (eNULL) are not offered.
* The minimum cipher key length offered is 112 bits. The maximum is 256 bits. Diffie-Hellman ciphers use a 2048-bit key for forward secrecy.

Additionally:

* SMTP Submission (port 587) will not accept user credentials without STARTTLS (true also of SMTP on port 25 in case of client misconfiguration), and the submission port won't accept mail without encryption. The minimum cipher key length is 128 bits. (The box is of course configured not to be an open relay. User credentials are required to send outbound mail.) ([source](setup/mail-postfix.sh))
* HTTPS (port 443): The HTTPS Strict Transport Security header is set. A redirect from HTTP to HTTPS is offered. The [Qualys SSL Labs test](https://www.ssllabs.com/ssltest) should report an A+ grade. ([source 1](conf/nginx-ssl.conf), [source 2](conf/nginx.conf))

For more details, see the [output of SSLyze for these ports](tests/tls_results.txt).

The cipher and protocol selection are chosen to support the following clients:

* For HTTPS: Firefox 1, Chrome 1, IE 7, Opera 5, Safari 1, Windows XP IE8, Android 2.3, Java 7.
* For other protocols: TBD.

### Password Storage

The passwords for mail users are stored on disk using the [SHA512-CRYPT](http://man7.org/linux/man-pages/man3/crypt.3.html) hashing scheme. ([source](management/mailconfig.py))

### Console access

Console access (e.g. via SSH) is configured by the system image used to create the box, typically from by a cloud virtual machine provider (e.g. Digital Ocean). Mail-in-a-Box does not set any console access settings, although it will warn the administrator in the System Status Checks if password-based login is turned on.

The [setup guide video](https://mailinabox.email/) explains how to verify the host key fingerprint on first login.

If DNSSEC is enabled at the box's domain name's registrar, the SSHFP record that the box automatically puts into DNS can also be used to verify the host key fingerprint by setting `VerifyHostKeyDNS yes` in your `ssh/.config` file or by logging in with `ssh -o VerifyHostKeyDNS=yes`. ([source](management/dns_update.py))

Outbound Mail
-------------

### Domain Policy Records

Domain policy records allow recipient MTAs to detect when the _domain_ part of incoming mail has been spoofed. All outbound mail is signed with [DKIM](https://en.wikipedia.org/wiki/DomainKeys_Identified_Mail) and "quarantine" [DMARC](https://en.wikipedia.org/wiki/DMARC) records are automatically set in DNS. Receiving MTAs that implement DMARC will automatically quarantine mail that is "From:" a domain hosted by the box but which was not sent by the box. (Strong [SPF](https://en.wikipedia.org/wiki/Sender_Policy_Framework) records are also automatically set in DNS.) ([source](management/dns_update.py))

### Encryption

The basic protocols of email delivery did not plan for the need for encryption. For a number of reasons it is not possible in most cases to guarantee that a connection to a recipient server is secure. However, the box --- along with the vast majority of mail servers --- uses [opportunistic encryption](https://en.wikipedia.org/wiki/Opportunistic_encryption), meaning the mail is encrypted in transit and protected from passive eavesdropping, but it is not protected from an active man-in-the-middle attack. Modern encryption settings will be used to the extent the recipient server supports them. ([source](setup/mail-postfix.sh))

### DANE

The box is [DNSSEC](https://en.wikipedia.org/wiki/DNSSEC)-aware (via a locally running DNSSEC-aware nameserver). When sending outbound mail, if the recipient's domain name supports DNSSEC and has published a [DANE TLSA](https://en.wikipedia.org/wiki/DNS-based_Authentication_of_Named_Entities) record, which contains a certificate fingerprint, the receiving MTA (server) must support TLS and its certificate must match the fingerprint. In other words, when a DANE TLSA record is published by the recipient, then on-the-wire encryption is forced between the box and the recipient MTA. ([source](setup/mail-postfix.sh))

Incoming Mail
-------------

### Encryption

As discussed above, there is no way to require on-the-wire encryption of mail. When the box receives an incoming email (SMTP on port 25), it offers encryption (STARTTLS) but cannot require that senders use it because some senders may not support STARTTLS at all and other senders may support STARTTLS but not with the latest protocols/ciphers. To give senders the best chance at making use of encryption, the box offers protocols back to SSLv3 and ciphers with key lengths as low as 112 bits. Modern clients (senders) will make use of the 256-bit ciphers and Diffie-Hellman ciphers with a 2048-bit key for forward secrecy, however. ([source](setup/mail-postfix.sh))

### DANE

When DNSSEC is enabled at the box's domain name's registrar, [DANE TLSA](https://en.wikipedia.org/wiki/DNS-based_Authentication_of_Named_Entities) records are automatically published in DNS. Senders supporting DANE will enforce encryption on-the-wire between them and the box --- see the section on DANE for outgoing mail above. ([source](management/dns_update.py))

### Filters

Incoming mail is run through several filters. Email is bounced if the sender's IP address is listed in the [Spamhaus Zen blacklist](http://www.spamhaus.org/zen/) or if the sender's domain is listed in the [Spamhaus Domain Block List](http://www.spamhaus.org/dbl/). Greylisting (with [postgrey](http://postgrey.schweikert.ch/)) is also used to cut down on spam. ([source](setup/mail-postfix.sh))
