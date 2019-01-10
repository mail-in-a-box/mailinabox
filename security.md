Mail-in-a-Box Security Guide
============================

Mail-in-a-Box turns a fresh Ubuntu 18.04 LTS 64-bit machine into a mail server appliance by installing and configuring various components.

This page documents the security features of Mail-in-a-Box. The term “box” is used below to mean a configured Mail-in-a-Box.

Threat Model
------------

Nothing is perfectly secure, and an adversary with sufficient resources can always penetrate a system.

The primary goal of Mail-in-a-Box is to make deploying a good mail server easy, so we balance ― as everyone does ― privacy and security concerns with the practicality of actually deploying the system. That means we make certain assumptions about adversaries. We assume that adversaries . . .

* Do not have physical access to the box (i.e., we do not aim to protect the box from physical access).
* Have not been given Unix accounts on the box (i.e., we assume all users with shell access are trusted).

On the other hand, we do assume that adversaries are performing passive surveillance and, possibly, active man-in-the-middle attacks. And so:

* User credentials are always sent through SSH/TLS, never in the clear, with modern TLS settings.
* Outbound mail is sent with the highest level of TLS possible.
* The box advertises its support for [DANE TLSA](https://en.wikipedia.org/wiki/DNS-based_Authentication_of_Named_Entities), when DNSSEC is enabled at the domain name registrar, so that inbound mail is more likely to be transmitted securely.

Additional details follow.

User Credentials
----------------

The box's administrator and its (non-administrative) mail users must sometimes communicate their credentials to the box.

### Services behind TLS

These services are protected by [TLS](https://en.wikipedia.org/wiki/Transport_Layer_Security):

* SMTP Submission (port 587). Mail users submit outbound mail through SMTP with STARTTLS on port 587.
* IMAP/POP (ports 993, 995). Mail users check for incoming mail through IMAP or POP over TLS.
* HTTPS (port 443). Webmail, the Exchange/ActiveSync protocol, the administrative control panel, and any static hosted websites are accessed over HTTPS.

The services all follow these rules:

* TLS certificates are generated with 2048-bit RSA keys and SHA-256 fingerprints. The box provides a self-signed certificate by default. The [setup guide](https://mailinabox.email/guide.html) explains how to verify the certificate fingerprint on first login. Users are encouraged to replace the certificate with a proper CA-signed one. ([source](setup/ssl.sh))
* Only TLSv1, TLSv1.1 and TLSv1.2 are offered (the older SSL protocols are not offered).
* HTTPS, IMAP, and POP track the [Mozilla Intermediate Ciphers Recommendation](https://wiki.mozilla.org/Security/Server_Side_TLS), balancing security with supporting a wide range of mail clients. Diffie-Hellman ciphers use a 2048-bit key for forward secrecy. For more details, see the [output of SSLyze for these ports](tests/tls_results.txt).
* SMTP (port 25) uses the Postfix medium grade ciphers and SMTP Submission (port 587) uses the Postfix high grade ciphers ([more info](http://www.postfix.org/postconf.5.html#smtpd_tls_mandatory_ciphers)).

Additionally:

* SMTP Submission (port 587) will not accept user credentials without STARTTLS (true also of SMTP on port 25 in case of client misconfiguration), and the submission port won't accept mail without encryption. The minimum cipher key length is 128 bits. (The box is of course configured not to be an open relay. User credentials are required to send outbound mail.) ([source](setup/mail-postfix.sh))
* HTTPS (port 443): The HTTPS Strict Transport Security header is set. A redirect from HTTP to HTTPS is offered. The [Qualys SSL Labs test](https://www.ssllabs.com/ssltest) should report an A+ grade. ([source 1](conf/nginx-ssl.conf), [source 2](conf/nginx.conf))

### Password Storage

The passwords for mail users are stored on disk using the [SHA512-CRYPT](http://man7.org/linux/man-pages/man3/crypt.3.html) hashing scheme. ([source](management/mailconfig.py))

When using the web-based administrative control panel, after logging in an API key is placed in the browser's local storage (rather than, say, the user's actual password). The API key is an HMAC based on the user's email address and current password, and it is keyed by a secret known only to the control panel service. By resetting an administrator's password, any HMACs previously generated for that user will expire.

### Console access

Console access (e.g. via SSH) is configured by the system image used to create the box, typically from by a cloud virtual machine provider (e.g. Digital Ocean). Mail-in-a-Box does not set any console access settings, although it will warn the administrator in the System Status Checks if password-based login is turned on.

The [setup guide video](https://mailinabox.email/) explains how to verify the host key fingerprint on first login.

If DNSSEC is enabled at the box's domain name's registrar, the SSHFP record that the box automatically puts into DNS can also be used to verify the host key fingerprint by setting `VerifyHostKeyDNS yes` in your `ssh/.config` file or by logging in with `ssh -o VerifyHostKeyDNS=yes`. ([source](management/dns_update.py))

### Brute-force attack mitigation

`fail2ban` provides some protection from brute-force login attacks (repeated logins that guess account passwords) by blocking offending IP addresses at the network level.

The following services are protected: SSH, IMAP (dovecot), SMTP submission (postfix), webmail (roundcube), Nextcloud/CalDAV/CardDAV (over HTTP), and the Mail-in-a-Box control panel & munin (over HTTP).

Some other services running on the box may be missing fail2ban filters.

`fail2ban` only blocks IPv4 addresses, however. If the box has a public IPv6 address, it is not protected from these attacks.

Outbound Mail
-------------

The basic protocols of email delivery did not plan for the presence of adversaries on the network. For a number of reasons it is not possible in most cases to guarantee that a connection to a recipient server is secure.

### DNSSEC

The first step in resolving the destination server for an email address is performing a DNS look-up for the MX record of the domain name. The box uses a locally-running [DNSSEC](https://en.wikipedia.org/wiki/DNSSEC)-aware nameserver to perform the lookup. If the domain name has DNSSEC enabled, DNSSEC guards against DNS records being tampered with.

### Encryption

The box (along with the vast majority of mail servers) uses [opportunistic encryption](https://en.wikipedia.org/wiki/Opportunistic_encryption), meaning the mail is encrypted in transit and protected from passive eavesdropping, but it is not protected from an active man-in-the-middle attack. Modern encryption settings (TLSv1 and later, no RC4) will be used to the extent the recipient server supports them. ([source](setup/mail-postfix.sh))

### DANE

If the recipient's domain name supports DNSSEC and has published a [DANE TLSA](https://en.wikipedia.org/wiki/DNS-based_Authentication_of_Named_Entities) record, then on-the-wire encryption is forced between the box and the recipient MTA and this encryption is not subject to a man-in-the-middle attack. The TLSA record contains a certificate fingerprint which the receiving MTA (server) must present to the box. ([source](setup/mail-postfix.sh))

### Domain Policy Records

Domain policy records allow recipient MTAs to detect when the _domain_ part of of the sender address in incoming mail has been spoofed. All outbound mail is signed with [DKIM](https://en.wikipedia.org/wiki/DomainKeys_Identified_Mail) and "quarantine" [DMARC](https://en.wikipedia.org/wiki/DMARC) records are automatically set in DNS. Receiving MTAs that implement DMARC will automatically quarantine mail that is "From:" a domain hosted by the box but which was not sent by the box. (Strong [SPF](https://en.wikipedia.org/wiki/Sender_Policy_Framework) records are also automatically set in DNS.) ([source](management/dns_update.py))

### User Policy

While domain policy records prevent other servers from sending mail with a "From:" header that matches a domain hosted on the box (see above), those policy records do not guarnatee that the user portion of the sender email address matches the actual sender. In enterprise environments where the box may host the mail of untrusted users, it is important to guard against users impersonating other users.

The box restricts the envelope sender address (also called the return path or MAIL FROM address --- this is different from the "From:" header) that users may put into outbound mail. The envelope sender address must be either their own email address (their SMTP login username) or any alias that they are listed as a permitted sender of. (There is currently no restriction on the contents of the "From:" header.)

Incoming Mail
-------------

### Encryption

As discussed above, there is no way to require on-the-wire encryption of mail. When the box receives an incoming email (SMTP on port 25), it offers encryption (STARTTLS) but cannot require that senders use it because some senders may not support STARTTLS at all and other senders may support STARTTLS but not with the latest protocols/ciphers. To give senders the best chance at making use of encryption, the box offers protocols back to TLSv1 and ciphers with key lengths as low as 112 bits. Modern clients (senders) will make use of the 256-bit ciphers and Diffie-Hellman ciphers with a 2048-bit key for perfect forward secrecy, however. ([source](setup/mail-postfix.sh))

### DANE

When DNSSEC is enabled at the box's domain name's registrar, [DANE TLSA](https://en.wikipedia.org/wiki/DNS-based_Authentication_of_Named_Entities) records are automatically published in DNS. Senders supporting DANE will enforce encryption on-the-wire between them and the box --- see the section on DANE for outgoing mail above. ([source](management/dns_update.py))

### Filters

Incoming mail is run through several filters. Email is bounced if the sender's IP address is listed in the [Spamhaus Zen blacklist](http://www.spamhaus.org/zen/) or if the sender's domain is listed in the [Spamhaus Domain Block List](http://www.spamhaus.org/dbl/). Greylisting (with [postgrey](http://postgrey.schweikert.ch/)) is also used to cut down on spam. ([source](setup/mail-postfix.sh))
