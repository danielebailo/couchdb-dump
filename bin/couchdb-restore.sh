#!/bin/bash
##
#    AUTHOR: DANIELE BAILO
#    https://github.com/danielebailo
#    www.danielebailo.it
#
#    Contributers:
#     * dalgibbard - http://github.com/dalgibbard
#     * epos-eu    - http://github.com/epos-eu
##

## This script is to restore a couchdb database-file to a couchdb database instance.
## FILE should be:
##  1. result of a couchdb-dump.sh command
##  2. OR formatted as explained @ http://wiki.apache.org/couchdb/HTTP_Bulk_Document_API

## USAGE
## ** example: ./couchdb-restore.sh -H 127.0.0.1 -d mydb -f dumpedDB.json -u admin -p password

###################### CODE STARTS HERE ###################

##START: FUNCTIONS
usage() {
    echo
    echo "Usage: $0 -H <COUCHDB_HOST> -d <DB_NAME> -f <INPUT_FILE> [-u <username>] [-p <password>] [-P <port>] [-l <lines_per_batch>]"
    echo -e "\t-h   Display usage information."
    echo -e "\t-H   CouchDB URL. Can be provided with or without 'http://'"
    echo -e "\t-d   CouchDB Database name to import to."
    echo -e "\t-f   File containing json to import."
    echo -e "\t-l   Number of lines to process at a time. [Default: 5000]"
    echo -e "\t-P   Provide a port number for CouchDB [Default: 5984]"
    echo -e "\t-u   Provide a username for auth against CouchDB [Default: blank]"
    echo -e "\t-p   Provide a password for auth against CouchDB [Default: blank]"
    echo
    echo "Example: $0 -H 127.0.0.1 -d mydb -f dumpedDB.json -u admin -p password"
    echo
    exit 1
}
## END FUNCTIONS

# Catch no args:
if [ "x$1" = "x" ]; then
    usage
fi

# Default args
username=""
password=""
port=5984
lines=5000
OPTIND=1

while getopts ":h?H:d:f:l:u:p:P:" opt; do
    case "$opt" in
        h) usage;;
        H) url="$OPTARG" ;;
        d) db_name="$OPTARG" ;;
        f) file_name="$OPTARG" ;;
        l) lines="$OPTARG" ;;
        u) username="$OPTARG";;
        p) password="$OPTARG";;
        P) port="${OPTARG}";;
        :) echo "... ERROR: Option \"-${OPTARG}\" requires an argument"; usage ;;
        *|\?) echo "... ERROR: Unknown Option \"-${OPTARG}\""; usage;;
    esac
done

### VALIDATION START

# Trap unexpected extra args
shift $((OPTIND-1))
[ "$1" = "--" ] && shift
if [ ! "x$@" = "x" ]; then
    echo "... ERROR: Unknown Option \"$@\""
    usage
fi

# Handle empty args
# url
if [ "x$url" = "x" ]; then
    echo "... ERROR: Missing argument '-H <COUCHDB_HOST>'"
    usage
fi
# db_name
if [ "x$db_name" = "x" ]; then
    echo "... ERROR: Missing argument '-d <DB_NAME>'"
    usage
fi
# file_name
if [ "x$file_name" = "x" ]; then
    echo "... ERROR: Missing argument '-f <OUTPUT_FILE>'"
    usage
fi

## Manage the passing of http/https for $url:
if [ ! "`echo $url | grep -c http`" = 1 ]; then
    url="http://$url"
fi

# Manage the addition of port
# If a port isn't already on our URL...
if [ ! "`echo $url | egrep -c ":[0-9]*$"`" = "1" ]; then
    # add it.
    url="$url:$port"
fi

## Manage the addition of user+pass if needed:
# Ensure, if one is set, both are set.
if [ ! "x$username" = "x" ]; then
    if [ "x$password" = "x" ]; then
        echo "... ERROR: Password cannot be blank, if username is specified."
        usage
    fi
elif [ ! "x$password" = "x" ]; then
    if [ "x$username" = "x" ]; then
        echo "... ERROR: Username cannot be blank, if password is specified."
        usage
    fi
fi

# If neither username or password are empty, we need to add it to our URL.
if [ ! "x$username" = "x" ]&&[ ! "x$password" = "x" ]; then
    httptype="`echo $url | awk -F'/' '{print$1}'`"
    urlbase="`echo $url | awk -F'/' '{print$3}'`"
    url="${httptype}//${username}:${password}@${urlbase}"
fi

# Check if input exists:
if [ ! -f ${file_name} ]; then
    echo "... ERROR: Input file ${file_name} not found."
    exit 1
fi

#### VALIDATION END

## Stop bash mangling wildcard... 
set -o noglob
# Manage Design Documents as a priority, and remove them from the main import job
echo "... INFO: Separating Design documents"
# Find all _design docs, put them into another file
design_file_name=${file_name}.design
grep '^{"_id":"_design' ${file_name} > ${design_file_name}

# Count the design file (if it even exists)
DESIGNS="`wc -l ${design_file_name} 2>/dev/null | awk '{print$1}'`"
# If design docs were found for import...
if [ ! "x$DESIGNS" = "x" ]; then 
    echo "... INFO: Duplicating original file for alteration"
    # Duplicate the original DB file, so we don't mangle the user's input file:
    cp -f ${file_name}{,-nodesign}
    # Re-set file_name to be our new file.
    file_name=${file_name}-nodesign
    # Remove these design docs from (our new) main file.
    echo "... INFO: Stripping _design elements from regular documents"
    sed -i '/^{"_id":"_design/d' ${file_name}
    # Remove the final document's trailing comma
    echo "... INFO: Fixing end document"
    line=$(expr `wc -l ${file_name} | awk '{print$1}'` - 1)
    sed -i "${line}s/,$//" ${file_name}

    echo "... INFO: Inserting Design documents"
    designcount=0
    # For each design doc...
    while IFS="" read -r; do
        line="${REPLY}"
        # Split the ID out for use as the import URL path
        URLPATH=$(echo $line | awk -F'"' '{print$4}')
        # Scrap the ID and Rev from the main data, as well as any trailing ','
        echo "${line}" | sed -re "s@^\{\"_id\":\"${URLPATH}\",\"_rev\":\"[0-9]*-[0-9a-zA-Z_\-]*\",@\{@" | sed -e 's/,$//' > ${design_file_name}.${designcount}
        # Fix Windows CRLF
        if [ "`file ${design_file_name}.${designcount} | grep -c CRLF`" = "1" ]; then
            echo "... INFO: File contains Windows carridge returns- converting..."
            tr -d '\r' < ${design_file_name}.${designcount} > ${design_file_name}.${designcount}.tmp
            if [ $? = 0 ]; then
                mv ${design_file_name}.${designcount}.tmp ${design_file_name}.${designcount}
                if [ $? = 0 ]; then
                    echo "... INFO: Completed successfully."
                else
                    echo "... ERROR: Failed to overwrite ${design_file_name}.${designcount} with ${design_file_name}.${designcount}.tmp"
                    exit 1
                fi
            else
                echo ".. ERROR: Failed to convert file."
                exit 1
            fi
        fi

        # Insert this file into the DB
        curl -T ${design_file_name}.${designcount} -X PUT "${url}/${db_name}/${URLPATH}" -H 'Content-Type: application/json' -o ${design_file_name}.out.${designcount}
        # If curl threw an error:
        if [ ! $? = 0 ]; then
             echo "... ERROR: Curl failed trying to restore ${design_file_name}.${designcount} - Stopping"
             exit 1
        # If curl was happy, but CouchDB returned an error in the return JSON:
        elif [ ! "`head -n 1 ${design_file_name}.out.${designcount} | grep -c 'error'`" = 0 ]; then
             echo "... ERROR: CouchDB Reported: `head -n 1 ${design_file_name}.out.${designcount}`"
             exit 1
        # Otherwise, if everything went well, delete our temp files.
        else
             rm -f ${design_file_name}.out.${designcount}
             rm -f ${design_file_name}.${designcount}
        fi
        # Increase design count - mainly used for the INFO at the end.
        (( designcount++ ))
    # NOTE: This is where we insert the design lines exported from the main block
    done < <(cat ${design_file_name})
    echo "... INFO: Successfully imported ${designcount} Design Documents"
# If there were no design docs found for import:
else
    # Cleanup any null files
    rm -f ${design_file_name} 2>/dev/null
    echo "... INFO: No Design Documents found for import."
fi
set +o noglob

# If the size of the file to import is less than our $lines size, don't worry about splitting
if [ `wc -l $file_name | awk '{print$1}'` -lt $lines ]; then
    echo "... INFO: Small dataset. Importing as a single file."
    curl -T $file_name -X POST "$url/$db_name/_bulk_docs" -H 'Content-Type: application/json'
# Otherwise, it's a large import that requires bulk insertion.
else
    echo "... INFO: Block import set to ${lines} lines."
    if [ -f ${file_name}.split000000 ]; then
        echo "... ERROR: Split files \"${file_name}.split*\" already present. Please remove before continuing."
        exit 1
    fi

    echo "... INFO: Generating files to import"
    ### Split the file into many
    split --numeric-suffixes --suffix-length=6 -l ${lines} ${file_name} ${file_name}.split
    if [ ! "$?" = "0" ]; then
        echo "... ERROR: Unable to create split files."
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
                echo "... INFO: Adding header to ${PADNAME}"
                sed -i "1i${HEADER}" ${PADNAME}
            else
                echo "... INFO: Header already applied to ${PADNAME}"
            fi
            if [ ! "`tail -n 1 ${PADNAME}`" = "${FOOTER}" ]; then
                echo "... INFO: Adding footer to ${PADNAME}"
                sed -i '$s/,$//g' ${PADNAME}
                echo "${FOOTER}" >> ${PADNAME}
            else
                echo "... INFO: Footer already applied to ${PADNAME}"
            fi
            echo "... INFO: Inserting ${PADNAME}"
            curl -T ${PADNAME} -X POST "$url/$db_name/_bulk_docs" -H 'Content-Type: application/json' -o tmp.out
            if [ ! $? = 0 ]; then
                echo "... ERROR: Curl failed trying to restore ${PADNAME} - Stopping"
                exit 1
            elif [ ! "`head -n 1 tmp.out | grep -c 'error'`" = 0 ]; then
                echo "... ERROR: CouchDB Reported: `head -n 1 tmp.out`"
                exit 1
            else
                rm -f ${PADNAME}
                rm -f tmp.out
            fi
            (( NUM++ ))
        else
            echo "... INFO: Successfully Imported `expr ${NUM} - 1` Files"
            A=1
        fi
    done
fi
