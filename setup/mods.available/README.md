This directory contains optional scripts that are run as part of setup (as the last step). They are disabled by default. To use them, create a `local` directory containing symbolic links to the mods you care to enable.

For example, to add coturn support for Nextcloud Talk do the following from the root directory of your installation:

```
setup/enmod.sh coturn
```

When `setup/start.sh` (or `ehdd/start-encrypted.sh`) are run, these scripts will be executed after setup has completed.

Before enabling any mod scripts from `setup/mods.available` (or elsewhere), be aware that they will likely modify your system, and that removal of the script from `local` will not restore the system to its pre-mod state. For example, enabling coturn, then removing the `local/coturn.sh` symlink, will not remove coturn from the system. It will still be active and enabled in systemd and firewall rules it added will still be in place.

**Before enabling any setup mod, it's very important that you look at the script and understand what it's doing and how to remove it.**

**USE OF SETUP MODS IS AT YOUR OWN RISK**

If you're creating your own setup mod, it should not store files in STORAGE_ROOT (/home/user-data) that are required at boot due to encryption-at-rest issues. With encryption-at-rest enabled, STORAGE_ROOT (/home/user-data) is not available until the encrypted drive has been mounted (the sysadmin has manually keyed in the EHDD drive password) and any mod with a system service that starts without the drive available may fail or behave in unexpected ways.

If you wish to contribute your own mod, please create a PR to add it
to this directory. Ensure the script contains the author's name, when
it was last updated, requirements for running the script, and how to
remove it. Please note that this project is GPL and any contributions
will fall under that license.

