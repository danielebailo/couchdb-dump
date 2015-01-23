Couchdb-dump (& restore)
============

It works on LINUX/UNIX, Bash based systems (MacOSx)

**Bash command line script(s) to EASILY dump&restore a CouchDB database**

 * Needs bash
 * Dumped database is output to a file (configurable).

##Quickstart (& quickend)
* Dump:

```bash couchdb-dump.sh -H 127.0.0.1 -d my-db -f dumpedDB.json -u admin -p password```

* Restore:

```bash couchdb-restore.sh -H 127.0.0.1 -d my-db -f dumpedDB.json -u admin -p password```

## Why do you need it?
Surprisingly, there is not a straightforward way to dump a CouchDB database. Often you are suggested to replicate it or to dump it with the couchdb `_all_docs` directive. 

**But, using the `_all_docs` directive provides you with JSON which cannot be directly re-import back into CouchDB**.

Hence, the goal of this script(s) is to give you a simple way to Dump & Restore your CouchDB database.

## What can't it do?
Unfortunately, the script doesn't currently handle binary attachments- and documents which contain them will fail to import- ie:

```
{"docs":[
{"_id":"4685ca2ba841112ed63ba386c0001e56","_rev":"2-e1432ed19858cdbc8b5c0c0bbf38f76a","value":"this is my binary document","_attachments":{"esxi.tgz":{"content_type":"application/x-compressed-tar","revpos":2,"digest":"md5-K1F3CiyZT2AjIaR3n7dFSQ==","length":1697995,"stub":true}}}
]}
```

Results in:

```
{"error":"missing_stub","reason":"id:4685ca2ba841112ed63ba386c0001e56, name:esxi.tgz"}
```

This is a known limitation, and is discussed in #2

## DUMP Usage
```
Usage: ./couchdb-dump.sh -H <COUCHDB_HOST> -d <DB_NAME> -f <OUTPUT_FILE> [-u <username>] [-p <password>] [-P <port>]
	-H   CouchDB URL. Can be provided with or without 'http://'
	-d   CouchDB Database name to dump.
	-f   File to write Database to.
	-P   Provide a port number for CouchDB [Default: 5984]
	-u   Provide a username for auth against CouchDB [Default: blank]
	-p   Provide a password for auth against CouchDB [Default: blank]
	-V   Display version information.
	-h   Display usage information.

Example: ./couchdb-dump.sh ./couchdb-dump.sh -H 127.0.0.1 -d mydb -f dumpedDB.json -u admin -p password
```

## RESTORE usage
```
Usage: ./couchdb-restore.sh -H <COUCHDB_HOST> -d <DB_NAME> -f <INPUT_FILE> [-u <username>] [-p <password>] [-P <port>] [-l <lines_per_batch>]
	-H   CouchDB URL. Can be provided with or without 'http://'
	-d   CouchDB Database name to import to.
	-f   File containing json to import.
	-l   Number of lines to process at a time. [Default: 5000]
	-P   Provide a port number for CouchDB [Default: 5984]
	-u   Provide a username for auth against CouchDB [Default: blank]
	-p   Provide a password for auth against CouchDB [Default: blank]
	-V   Display version information.
	-h   Display usage information.

Example: ./couchdb-restore.sh -H 127.0.0.1 -d mydb -f dumpedDB.json -u admin -p password
```
