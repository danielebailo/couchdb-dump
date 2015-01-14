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
## ** example: bash couchdb-restore mycouch.com my-db dumpedDB.txt**
# syntax: bash couchdb-dump URL... DB_NAME... DUMPED_DB_FILENAME...
## DB_URL: the url of the couchdb instance without 'http://', e.g. mycouch.com
## DB_NAME: name of the database, e.g. 'my-db
## DUMPED_DB_FILENAME... : file containing the JSON object with all the docs





###################### CODE STARTS HERE ###################

##START: HELPERS FUNCTIONS
function helpMsg {
	echo "** usage: bash couchdb-restore DB_URL... DB_NAME... DUMPED_DB_FILENAME..."
	echo "**  example: bash couchdb-restore.sh mycouch.com my-db dumpedDB.txt 10000"
    echo "**  DB_URL: the url of the couchdb instance without 'http://', e.g. mycouch.com"
    echo "**  DB_NAME: name of the database, e.g. 'my-db'"
    echo "**  DUMPED_DB_FILENAME... : file containing the JSON object with all the docs, e.g. dumpedDB.txt"
    echo "**  BULK_QUANTITY : number of lines to process at a time. eg 10000 lines-per-POST"

	}


##NO ARGS
if [ $# -lt 3 ]; then
	echo ":::::::::::::::::::::::::::::::::::::::::"
     echo 1>&2 "** $0: not enough arguments"
     helpMsg
     exit 2
elif [ $# -gt 4 ]; then
	echo ""
     echo 1>&2 "$0: too many arguments"
     helpMsg
fi



## VARS
url=$1
db_name=$2
file_name=$3
lines=$4

if [ "x$lines" = "x" ]||[ `wc -l $file_name | awk '{print$1}'` -lt $lines ]; then
	curl -d @$file_name -X POST http://$url:5984/$db_name/_bulk_docs -H 'Content-Type: application/json'
else
	echo "Block import set to $lines"
	if [ -f ${file_name}.split000000 ]; then
		echo "Split files already present. Not continuing."
		exit 1
	fi
	echo "Generating files to import..."
	### Split the file into many
	split --numeric-suffixes --suffix-length=6 -l ${lines} ${file_name} ${file_name}.split
	if [ ! "$?" = "0" ]; then
		echo "Error encountered whilst trying to create split files."
		exit 1
	fi
	HEADER="`head -n 1 $file_name`"
	FOOTER="`tail -n 1 $file_name`"
	
	A=0
	NUM=0
	until [ $A = 1 ];do
		PADNUM=`printf "%06d" $NUM`
		PADNAME="${file_name}.split${PADNUM}"
		if [ -f ${PADNAME} ]; then
			if [ ! "`head -n 1 ${PADNAME}`" = "${HEADER}" ]; then
				echo "Adding header to ${PADNAME}"
				sed -i "1i${HEADER}" ${PADNAME}
			else
				echo "Header already applied to ${PADNAME}"
			fi
			if [ ! "`tail -n 1 ${PADNAME}`" = "${FOOTER}" ]; then
				echo "Adding footer to ${PADNAME}"
				sed -i '$s/,$//g' ${PADNAME}
				echo "${FOOTER}" >> ${PADNAME}
			else
				echo "Footer already applied to ${PADNAME}"
			fi
			echo "Inserting ${PADNAME}"
			curl -d @${PADNAME} -X POST http://$url:5984/$db_name/_bulk_docs -H 'Content-Type: application/json'
			if [ ! $? = 0 ]; then
				echo "An error was encountered whilst attempting to restore ${PADNAME} - Stopping"
				exit 1
			else
				rm -f ${PADNAME}
			fi
			(( NUM++ ))
		else
			echo "Imported `expr ${NUM} - 1` Files"
			A=1
		fi
	done
fi
