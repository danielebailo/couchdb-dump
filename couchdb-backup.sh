#!/bin/bash
##
#    AUTHOR: DANIELE BAILO
#    https://github.com/danielebailo
#    www.danielebailo.it
#
#    Contributors:
#     * dalgibbard - http://github.com/dalgibbard
#     * epos-eu    - http://github.com/epos-eu
##

## This script allow for the Backup and Restore of a CouchDB Database.
## Backups are produced in a format that can be later uploaded with the bulk docs directive (as used by this script)

## USAGE
## * To Backup:
## ** example: ./couchdb-backup.sh -b -H 127.0.0.1 -d mydb -u admin -p password -f mydb.json
## * To Restore:
## ** example: ./couchdb-backup.sh -r -H 127.0.0.1 -d mydb -u admin -p password -f mydb.json


###################### CODE STARTS HERE ###################
scriptversionnumber="1.0.0"

##START: FUNCTIONS
usage(){
    echo
    echo "Usage: $0 [-b|-r] -H <COUCHDB_HOST> -d <DB_NAME> -f <BACKUP_FILE> [-u <username>] [-p <password>] [-P <port>] [-l <lines>] [-t <threads>]"
    echo -e "\t-b   Run script in BACKUP mode."
    echo -e "\t-r   Run script in RESTORE mode."
    echo -e "\t-H   CouchDB Hostname or IP. Can be provided with or without 'http(s)://'"
    echo -e "\t-d   CouchDB Database name to backup/restore."
    echo -e "\t-f   File to Backup-to/Restore-from."
    echo -e "\t-P   Provide a port number for CouchDB [Default: 5984]"
    echo -e "\t-u   Provide a username for auth against CouchDB [Default: blank]"
    echo -e "\t-p   Provide a password for auth against CouchDB [Default: blank]"
    echo -e "\t-l   Number of lines (documents) to Restore at a time. [Default: 5000] (Restore Only)"
    echo -e "\t-t   Number of CPU threads to use when parsing data [Default: nProcs-1] (Backup Only)"
    echo -e "\t-V   Display version information."
    echo -e "\t-h   Display usage information."
    echo
    echo "Example: $0 -b -H 127.0.0.1 -d mydb -f dumpedDB.json -u admin -p password"
    echo
    exit 1
}

scriptversion(){
    echo
    echo -e "\t** couchdb-dump version: $scriptversionnumber **"
    echo
    echo -e "\t URL:\thttps://github.com/danielebailo/couchdb-dump"
    echo
    echo -e "\t Authors:"
    echo -e "\t Daniele Bailo  (bailo.daniele@gmail.com)"
    echo -e "\t Darren Gibbard (dalgibbard@gmail.com)"
    echo
    exit 1
}

checkdiskspace(){
## This function checks available diskspace for a required path, vs space required
## Example call:   checkdiskspace /path/to/file/to/create 1024
    location=$1
    KBrequired=$2
    if [ "x$location" = "x" ]||[ "x$KBrequired" = "x" ]; then
        echo "... ERROR: checkdiskspace() was not passed the correct arguments."
        exit 1
    fi

    stripdir=${location%/*}
    KBavail=$(df -P -BK ${stripdir} | tail -n 1 | awk '{print$4}' | sed -e 's/K$//')

    if [ $KBavail -ge $KBrequired ]; then
        return 0
    else
        echo
        echo "... ERROR: Insufficient Disk Space Available:"
        echo "        * Full Path:            ${location}"
        echo "        * Affected Directory:   ${stripdir}"
        echo "        * Space Available:      ${KBavail} KB"
        echo "        * Total Space Required: ${KBrequired} KB"
        echo "        * Additional Space Req: $(expr $KBrequired - $KBavail) KB"
        echo
        exit 1
    fi
}
## END FUNCTIONS

# Catch no args:
if [ "x$1" = "x" ]; then
    usage
fi

# Default Args
username=""
password=""
backup=false
restore=false
port=5984
OPTIND=1
lines=5000

while getopts ":h?H:d:f:u:p:P:l:t:V?b?B?r?R?" opt; do
    case "$opt" in
        h) usage;;
        b|B) backup=true ;;
        r|R) restore=true ;;
        H) url="$OPTARG" ;;
        d) db_name="$OPTARG" ;;
        f) file_name="$OPTARG" ;;
        u) username="$OPTARG";;
        p) password="$OPTARG";;
        P) port="${OPTARG}";;
        l) lines="${OPTARG}" ;;
        t) threads="${OPTARG}" ;;
        V) scriptversion;;        
        :) echo "... ERROR: Option \"-${OPTARG}\" requires an argument"; usage ;;
        *|\?) echo "... ERROR: Unknown Option \"-${OPTARG}\""; usage;;
    esac
done

# Trap unexpected extra args
shift $((OPTIND-1))
[ "$1" = "--" ] && shift
if [ ! "x$@" = "x" ]; then
    echo "... ERROR: Unknown Option \"$@\""
    usage
fi

# Handle invalid backup/restore states:
if [ $backup = true ]&&[ $restore = true ]; then
    echo "... ERROR: Cannot pass both '-b' and '-r'"
    usage
elif [ $backup = false ]&&[ $restore = false ]; then
    echo "... ERROR: Missing argument '-b' (Backup), or '-r' (Restore)"
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
    echo "... ERROR: Missing argument '-f <FILENAME>'"
    usage
fi

# Validate thread count
cores=`nproc`
if [ ! "x$threads" = "x" ]; then
    if [ $threads -gt $cores ]; then
        echo "... WARN: Thread setting of $threads is more than CPU count. Setting to $cores"
        threads=$cores
    else
        echo "... INFO: Setting parser threads to $threads"
    fi
else
    threads=`expr $cores - 1`
fi

## Manage the passing of http/https for $url:
# Note; if the user wants to use 'https://' they must specify it exclusively in the '-H <HOSTNAME>' arg.
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

# Allow for self-signed/invalid certs if method is HTTPS:
if [ "`echo $url | grep -ic "^https://"`" = "1" ]; then
	curlopt="-k"
fi

### If user selected BACKUP, run the following code:
if [ $backup = true ]&&[ $restore = false ]; then
    #################################################################
    ##################### BACKUP START ##############################
    #################################################################
    # Check if output already exists:
    if [ -f ${file_name} ]; then
        echo "... ERROR: Output file ${file_name} already exists."
        exit 1
    fi

    # Grab our data from couchdb
    curl ${curlopt} -X GET "$url/$db_name/_all_docs?include_docs=true" -o ${file_name}
    # Check for curl errors
    if [ ! $? = 0 ]; then
        echo "... ERROR: Curl encountered an issue whilst dumping the database."
        rm -f ${file_name} 2>/dev/null
        exit 1
    fi
    # Check for export errors
    ERR_CHECK="`head -n 1 ${file_name} | grep '^{"error'`"
    if [ ! "x${ERR_CHECK}" = "x" ]; then
        echo "... ERROR: CouchDB reported: $ERR_CHECK"
        exit 1
    fi

    # CouchDB has a tendancy to output Windows carridge returns in it's output -
    # This messes up us trying to sed things at the end of lines!
    if [ "`file $file_name | grep -c CRLF`" = "1" ]; then
        echo "... INFO: File contains Windows carridge returns- converting..."
        filesize=$(du -P -BK ${file_name} | awk '{print$1}' | sed -e 's/K$//')
        checkdiskspace "${file_name}" $filesize
        tr -d '\r' < ${file_name} > ${file_name}.tmp
        if [ $? = 0 ]; then
            mv ${file_name}.tmp ${file_name}
            if [ $? = 0 ]; then
                echo "... INFO: Completed successfully."
            else
                echo "... ERROR: Failed to overwrite ${file_name} with ${file_name}.tmp"
                exit 1
            fi
        else
            echo ".. ERROR: Failed to convert file."
            exit 1
        fi
    fi

    ## Now we parse the output file to make it suitable for re-import.
    echo "... INFO: Amending file to make it suitable for Import."
    echo "... INFO: Stage 1 - Document filtering"

    # If the input file is larger than 250MB, multi-thread the parsing:
    if [ $(du -P -BK ${file_name} | awk '{print$1}' | sed -e 's/K$//') -ge 256000 ]&&[ ! $threads -le 1 ]; then
        filesize=$(du -P -BK ${file_name} | awk '{print$1}' | sed -e 's/K$//')
        KBreduction=$(($((`wc -l ${file_name} | awk '{print$1}'` * 80)) / 1024))
        filesize=`expr $filesize + $(expr $filesize - $KBreduction)`
        checkdiskspace "${file_name}" $filesize
        echo "... INFO: Multi-Threading Parsing Enabled."
        if [ -f ${file_name}.thread000000 ]; then
            echo "... ERROR: Split files \"${file_name}.thread*\" already present. Please remove before continuing."
            exit 1
        elif [ -f ${file_name}.tmp ]; then
            echo "... ERROR: Tempfile ${file_name}.tmp already present. Please remove before continuing."
            exit 1
        fi

        ### SPLIT INTO THREADS
        split_cal=$(( $((`wc -l ${file_name} | awk '{print$1}'` / $threads)) + $threads ))
        split --numeric-suffixes --suffix-length=6 -l ${split_cal} ${file_name} ${file_name}.thread
        if [ ! "$?" = "0" ]; then
            echo "... ERROR: Unable to create split files."
            exit 1
        fi

        NUM=0
        for loop in `seq 1 ${threads}`; do
            PADNUM=`printf "%06d" $NUM`
            PADNAME="${file_name}.thread${PADNUM}"
            sed -i 's/.*,"doc"://g' ${PADNAME} &
            (( NUM++ ))
        done
        wait
        NUM=0
        for loop in `seq 1 ${threads}`; do
            PADNUM=`printf "%06d" $NUM`
            PADNAME="${file_name}.thread${PADNUM}"
            cat ${PADNAME} >> ${file_name}.tmp
            rm -f ${PADNAME}
            (( NUM++ ))
        done
        if [ `wc -l ${file_name} | awk '{print$1}'` = `wc -l ${file_name}.tmp | awk '{print$1}'` ]; then
            mv ${file_name}{.tmp,}
            if [ ! $? = 0 ]; then
                echo "... ERROR: Failed to overwrite ${file_name}"
                exit 1
            fi
        else
            echo "... ERROR: Multi-threaded data parsing encountered an error."
            exit 1
        fi

    else
        # Estimating 80byte saving per line... probably a little conservative depending on keysize.
        KBreduction=$(($((`wc -l ${file_name} | awk '{print$1}'` * 80)) / 1024))
        filesize=$(du -P -BK ${file_name} | awk '{print$1}' | sed -e 's/K$//')
        filesize=`expr $filesize - $KBreduction`
        checkdiskspace "${file_name}" $filesize
        sed -i 's/.*,"doc"://g' $file_name
        if [ ! $? = 0 ];then
            echo "Stage failed."
            exit 1
        fi
    fi

    echo "... INFO: Stage 2 - Duplicate curly brace removal"
    # Approx 1Byte per line removed
    KBreduction=$((`wc -l ${file_name} | awk '{print$1}'` / 1024))
    filesize=$(du -P -BK ${file_name} | awk '{print$1}' | sed -e 's/K$//')
    filesize=`expr $filesize - $KBreduction`
    checkdiskspace "${file_name}" $filesize
    sed -i 's/}},$/},/g' $file_name
    if [ ! $? = 0 ];then
        echo "Stage failed."
        exit 1
    fi
    echo "... INFO: Stage 3 - Header Correction"
    filesize=$(du -P -BK ${file_name} | awk '{print$1}' | sed -e 's/K$//')
    checkdiskspace "${file_name}" $filesize
    sed -i '1s/^.*/{"new_edits":false,"docs":[/' $file_name
    if [ ! $? = 0 ];then
        echo "Stage failed."
        exit 1
    fi
    echo "... INFO: Stage 4 - Final document line correction"
    filesize=$(du -P -BK ${file_name} | awk '{print$1}' | sed -e 's/K$//')
    checkdiskspace "${file_name}" $filesize
    sed -i 's/}}$/}/g' $file_name
    if [ ! $? = 0 ];then
        echo "Stage failed."
        exit 1
    fi

    echo "... INFO: Export completed successfully. File available at: ${file_name}"

### Else if user selected Restore:
elif [ $restore = true ]&&[ $backup = false ]; then
    #################################################################
    ##################### RESTORE START #############################
    #################################################################
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
        filesize=$(du -P -BK ${file_name} | awk '{print$1}' | sed -e 's/K$//')
        checkdiskspace "${file_name}" $filesize
        cp -f ${file_name}{,-nodesign}
        # Re-set file_name to be our new file.
        file_name=${file_name}-nodesign
        # Remove these design docs from (our new) main file.
        echo "... INFO: Stripping _design elements from regular documents"
        checkdiskspace "${file_name}" $filesize
        sed -i '/^{"_id":"_design/d' ${file_name}
        # Remove the final document's trailing comma
        echo "... INFO: Fixing end document"
        line=$(expr `wc -l ${file_name} | awk '{print$1}'` - 1)
        filesize=$(du -P -BK ${file_name} | awk '{print$1}' | sed -e 's/K$//')
        checkdiskspace "${file_name}" $filesize
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
                filesize=$(du -P -BK ${design_file_name}.${designcount} | awk '{print$1}' | sed -e 's/K$//')
                checkdiskspace "${file_name}" $filesize
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
        filesize=$(du -P -BK ${file_name} | awk '{print$1}' | sed -e 's/K$//')
        checkdiskspace "${file_name}" $filesize
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
                    filesize=$(du -P -BK ${PADNAME} | awk '{print$1}' | sed -e 's/K$//')
                    checkdiskspace "${PADNAME}" $filesize
                    sed -i "1i${HEADER}" ${PADNAME}
                else
                    echo "... INFO: Header already applied to ${PADNAME}"
                fi
                if [ ! "`tail -n 1 ${PADNAME}`" = "${FOOTER}" ]; then
                    echo "... INFO: Adding footer to ${PADNAME}"
                    filesize=$(du -P -BK ${PADNAME} | awk '{print$1}' | sed -e 's/K$//')
                    checkdiskspace "${PADNAME}" $filesize
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

# Capture if user managed to do something odd...
else
    echo "... ERROR: How did you get here??"
    exit 1
fi
