Couchdb-dump (& restore)
============

It works on LINUX/UNIX, Bash based systems (MacOSx)

**Bash command line script to EASILY Backup & Restore a CouchDB database**

 * Needs bash (plus curl, tr, file, split, awk, sed)
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

## NOTE

Attachments in Database documents are only supported in CouchDB 1.6+

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
        -c   Create DB on demand, if they are not listed.
        -z   Compress output file (Backup Only)
        -T   Add datetime stamp to output file name (Backup Only)
        -q   Run in quiet mode. Suppress output, except for errors and warnings.
        -V   Display version information.
        -h   Display usage information.

Example: ./couchdb-backup.sh -b -H 127.0.0.1 -d mydb -f dumpedDB.json -u admin -p password
```

### Bonus 1! Full Database Compaction
In the past, we've used this script to greatly compress a bloated database.
In our use case, we had non-sequential IDs which cause CouchDB's B-Tree to balloon out of control, even with daily compactions.

**How does this fix work?**
When running the export, all of the documents are pulled out in "ID Order"- When re-importing these (now sorted) documents again, the B-Tree can be created in a much more efficient manner. We've seen 15GB database files, containing only 2.1GB of raw JSON, reduced to 2.5GB on disk after import!

### Bonus 2! Purge Historic and Deleted Data
CouchDB is an append-only database. When you delete records, the metadata is maintained for future reference, and is never fully deleted. All documents also retain a historic revision count.
With the above points in mind; the export and import does not include Deleted documents, or old revisions; therefore, using this script, you can export and re-import your data, cleansing it of any previously (logically) deleted data!

If you pair this with deletion and re-creation of replication rules (using the 'update_seq' parameter to avoid re-pulling the entire DB/deleted documents from a remote node) you can manually compress and clean out an entire cluster of waste, node-by-node.
Note though; after creating all the rules with a fixed update_seq, once completed to the entire cluster, you will need to destroy and recreate all replication rules without the fixed update_seq - else, when restarting a node etc, replication will restart from the old seq.

