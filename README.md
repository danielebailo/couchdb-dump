Couchdb-dump (& restore)
============

It works on LINUX/UNIX, Bash based systems (MacOSx)

**Bash command line script to EASILY Backup & Restore a CouchDB database**

 * Needs bash
 * Dumped database is output to a file (configurable).

##Quickstart (& quickend)
* Backup:

```bash couchdb-backup.sh -b -H 127.0.0.1 -d my-db -f dumpedDB.json -u admin -p password```

* Restore:

```bash couchdb-backup.sh -r -H 127.0.0.1 -d my-db -f dumpedDB.json -u admin -p password```

## Why do you need it?
Surprisingly, there is not a straightforward way to dump a CouchDB database. Often you are suggested to replicate it or to dump it with the couchdb `_all_docs` directive. 

**But, using the `_all_docs` directive provides you with JSON which cannot be directly re-import back into CouchDB**.

Hence, the goal of this script(s) is to give you a simple way to Dump & Restore your CouchDB database.

## Usage
```
Usage: ./couchdb-backup.sh [-b|-r] -H <COUCHDB_HOST> -d <DB_NAME> -f <BACKUP_FILE> [-u <username>] [-p <password>] [-P <port>] [-l <lines>] [-t <threads>] [-a <import_attempts>]
        -b   Run script in BACKUP mode.
        -r   Run script in RESTORE mode.
        -H   CouchDB Hostname or IP. Can be provided with or without 'http(s)://'
        -d   CouchDB Database name to backup/restore.
        -f   File to Backup-to/Restore-from.
        -P   Provide a port number for CouchDB [Default: 5984]
        -u   Provide a username for auth against CouchDB [Default: blank]
        -p   Provide a password for auth against CouchDB [Default: blank]
        -l   Number of lines (documents) to Restore at a time. [Default: 5000] (Restore Only)
        -t   Number of CPU threads to use when parsing data [Default: nProcs-1] (Backup Only)
        -a   Number of times to Attempt import before failing [Default: 3] (Restore Only)
        -V   Display version information.
        -h   Display usage information.

Example: ./couchdb-backup.sh -b -H 127.0.0.1 -d mydb -f dumpedDB.json -u admin -p password
```
