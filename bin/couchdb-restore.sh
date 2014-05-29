#!/bin/bash
##
#    AUTHOR: DANIELE BAILO
#    https://github.com/danielebailo
#    www.danielebailo.it
##

## this script restore a couchdb database-file to a couchdb database instance
## FILE should be:
##  1. result of a couchdb-dump.sh command
##  2. OR formatted as explained @ http://wiki.apache.org/couchdb/HTTP_Bulk_Document_API


## USAGE
## ** example: bash coucdb-restore mycouch.com my-db dumpedDB.txt**
# syntax: bash couchdb-dump URL... DB_NAME... DUMPED_DB_FILENAME...
## DB_URL: the url of the couchdb instance without 'http://', e.g. mycouch.com
## DB_NAME: name of the database, e.g. 'my-db
## DUMPED_DB_FILENAME... : file containing the JSON object with all the docs





###################### CODE STARTS HERE ###################

##START: HELPERS FUNCTIONS
function helpMsg {
	echo "** usage: bash couchdb-restore DB_URL... DB_NAME... DUMPED_DB_FILENAME..."
	echo "**  example: bash couchdb-restore.sh mycouch.com my-db dumpedDB.txt"
    echo "**  DB_URL: the url of the couchdb instance without 'http://', e.g. mycouch.com"
    echo "**  DB_NAME: name of the database, e.g. 'my-db'"
    echo "**  DUMPED_DB_FILENAME... : file containing the JSON object with all the docs, e.g. dumpedDB.txt"

	}


##NO ARGS
if [ $# -lt 3 ]; then
	echo ":::::::::::::::::::::::::::::::::::::::::"
     echo 1>&2 "** $0: not enough arguments"
     helpMsg
     exit 2
elif [ $# -gt 3 ]; then
	echo ""
     echo 1>&2 "$0: too many arguments"
     helpMsg
fi



## VARS
url=$1
db_name=$2
file_name=$3




curl -d @$file_name -X POST http://$url:5984/$db_name/_bulk_docs -H 'Content-Type: application/json'
