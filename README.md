# Server Backups

Backup script & system for my server.

It comes with a free 100GB storage box that I use for backups. 

Based on [Hetzner's guide](https://community.hetzner.com/tutorials/install-and-configure-borgbackup).

TL;DR: The backup.sh script is a DIY solution that makes a bunch of pattern files by running `scripts/*`.
Those patterns are fed to Borg which does compression and deduplication.

Feel free to fork and use as you see fit. Released under The Unlicense. 

## Setup

Some important settings in Hetznet control panel:

- **Disable external access**
- Enable SSH support (for Borg)

Add an ssh config entry with the correct hostname, user and ssh key.

The script assumes the ssh connection can be setup using `backups` as host.
The path is set to `./borg/<hostname/`.

Create a `secrets.env` file (with `chown 600`!) next in this folder. Example contents:

```dotenv
BORG_PASSPHRASE=aHopefullyLongAndComplexPasphraseThatYouBackedUpOffline
POSTGRES_USER=postgres
MYSQL_USER=backup
MYSQL_PASS=thePassForAHopefullyLimitedAccount
EMAIL_RECIPIENTS=foo@bar.tld
```

## Scripts

All executables inside [scripts](./scripts) are run with a 2 minute timeout.

The scripts should assume their CWD is a tmp folder.
There is no resolution for conflicting filenames, so use sensibly long filenames.

The script must write compliant patterns to its first argument (a file).

For the format, check out `man borg-patterns` and/or <https://borgbackup.readthedocs.io/en/stable/usage/help.html>

## Automation

Automate the main script with cron.
