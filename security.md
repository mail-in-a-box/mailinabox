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

### Console access via SSH

Console access (e.g. via SSH) is configured by the system image used to create the box, typically from by a cloud virtual machine provider (e.g. Digital Ocean). Mail-in-a-Box does not set any console access settings, although it will warn the administrator in the System Status Checks if password-based login is turned on.

The [setup guide video](https://mailinabox.email/) explains how to verify the host key fingerprint on first login. If DNSSEC is enabled at the box's domain name's registrar, the SSHFP record that the box automatically puts into DNS can also be used to verify the host key fingerprint by setting `VerifyHostKeyDNS yes` in your `ssh/.config` file or by logging in with `ssh -o VerifyHostKeyDNS=yes`.

### Other services behind TLS

Other services are protected by TLS:

* SMTP Submission (port 587). Mail users submit outbound mail through SMTP with STARTTLS on port 587.
* IMAP/POP (ports 993, 995). Mail users check for incoming mail through IMAP or POP over TLS.
* HTTPS (port 443). Webmail, the Echange/ActiveSync protocol, the administrative control panel, and any static hosted websites are accessed over HTTPS.

These services all follow these rules:

* All of the services only offer TLSv1, TLSv1.1 and TLSv1.2 (the older SSL protocols are not offered).
* No services offer export-grade ciphers, the anonymous DH/ECDH algorithms (aNULL), or clear-text ciphers (eNULL).
* The minimum cipher key length offered is 112 bits. Diffie-Hellman ciphers use a 2048-bit key.
* The box provides a self-signed certificate by default. The [setup guide](https://mailinabox.email/guide.html) explains how to verify the certificate fingerprint on first login. Users are encouraged to replace the certificate with a proper CA-signed one, and when using the CSR provided by the box the certificates will use a SHA-2 hash.

Additionally:

* SMTP Submission (port 587) will not accept user credentials without STARTTLS. The minimum cipher key length is 128 bits.
* HTTPS (port 443): The HTTPS Strict Transport Security header is set. A redirect from HTTP to HTTPS is offered. The [Qualys SSL Labs test](https://www.ssllabs.com/ssltest) should report an A+ grade.

For more details, see the [output of SSLyze stored in github](tests/tls_results.txt).

Supported clients:

The cipher and protocol selection are chosen to support the following clients:

* For HTTPS: Firefox 1, Chrome 1, IE 7, Opera 5, Safari 1, Windows XP IE8, Android 2.3, Java 7.
* For other protocols: TBD.
