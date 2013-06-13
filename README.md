Couchdb-dump (& restore)
============

It works on LINUX/UNIX, Bash based systems (MacOSx)

**Bash command line script(s) to EASILY dump&restore a couchdb database and/or to restore it.**
 
NB: Dumped database is outputted in the stdout (screen)


##Quickstart (& quickend)
`Dump`: ***bash coucdb-dump mycouch.com my-db > dumped-db.txt***
`Restore`: ***bash coucdb-dump mycouch.com my-db dumpedDB.txt***


## Why do you need it?
Surprisingly there is not a straightforward way to dump a couchdb database. Often you are suggested to replicate it or to dump it with the couchdb `_all_docs` directive. 

**But using `_all_docs` directive you have as output a JSON object which cannot be used to directly re-upload the database to couchdb**.

Hence, the goal of this script(s) is to give you a simple way to download & upload your couchdb database.


## DUMP Usage

When launched it takes as arguments:

* url of database (without http://)
* database name

Just write in the command line:

***bash couchdb-dump DB_URL... DB_NAME...***

  `DB_URL`: the url of the couchdb instance without 'http://', e.g. mycouch.com
  
  `DB_NAME`: name of the database, e.g. 'my-db'


### Example

*bash coucdb-dump mycouch.com my-db*

**Saving output to file**

***bash coucdb-dump mycouch.com my-db > dumped-db.txt***


## RESTORE usage

When launched it takes as arguments:

* url of database (without http://)
* database name
* file containing dumped database

Just write in the command line:

***bash couchdb-dump URL... DB_NAME... DUMPED_DB_FILENAME...***

  `DB_URL`: the url of the couchdb instance without 'http://', e.g. mycouch.com
  
  `DB_NAME`: name of the database, e.g. 'my-db'
  
  `DUMPED_DB_FILENAME...` : file containing the JSON object with all the docs
  
  
  
### Example

***bash coucdb-dump mycouch.com my-db dumpedDB.txt***



## TODO
Add -p option to use an arbitrary port (5984 is the default one)

