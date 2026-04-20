#!/bin/bash


##
#    AUTHOR: DANIELE BAILO
#    https://github.com/danielebailo
#    www.danielebailo.it
#
#    Contributors:
#     * dalgibbard      - http://github.com/dalgibbard
#     * epos-eu         - http://github.com/epos-eu
#     * maximilianhuber - http://github.com/maximilianhuber
#     * ahodgkinson     - http://github.com/ahodgkinson (quiet-mode, timestamp, compress)
##

## This script allow for the Backup and Restore of a CouchDB Database.
## Backups are produced in a format that can be later uploaded with the bulk docs directive (as used by this script)

## USAGE
## * To Backup:
## ** example: ./couchdb-dump.sh -b -H 127.0.0.1 -d mydb -u admin -p password -f mydb.json
## * To Restore:
## ** example: ./couchdb-dump.sh -r -H 127.0.0.1 -d mydb -u admin -p password -f mydb.json


###################### CODE STARTS HERE ###################
scriptversionnumber="1.1.10"

# Path to relevant split command. On macos you should use perlpowertools split command to avoid compatibility issues with gnu-split.
split_command_path="split"

##START: FUNCTIONS
usage(){
    echo
    echo "Usage: $0 [-b|-r|-i] -H <COUCHDB_HOST> -d <DB_NAME> -f <BACKUP_FILE> [-u <username>] [-p <password>] [-P <port>] [-l <lines>] [-t <threads>] [-a <import_attempts>] [-s <start_at_filename>]"
    echo -e "\t-b   Run script in BACKUP mode."
    echo -e "\t-r   Run script in RESTORE mode."
    echo -e "\t-i   Run script in IMPORT-ONLY mode (import pre-split files, skip splitting/design docs)."
    echo -e "\t-n   No-transform mode: skip all file transformations (use with -i for pre-processed files)."
    echo -e "\t-D   Delay in seconds between imports (use with -i to prevent CouchDB overload)."
    echo -e "\t-H   CouchDB Hostname or IP. Can be provided with or without 'http(s)://'"
    echo -e "\t-d   CouchDB Database name to backup/restore."
    echo -e "\t-f   File to Backup-to/Restore-from."
    echo -e "\t-P   Provide a port number for CouchDB [Default: 5984]"
    echo -e "\t-u   Provide a username for auth against CouchDB [Default: blank]"
    echo -e "\t       -- can also set with 'COUCHDB_USER' environment var"
    echo -e "\t-p   Provide a password for auth against CouchDB [Default: blank]"
    echo -e "\t       -- can also set with 'COUCHDB_PASS' environment var"
    echo -e "\t-l   Number of lines (documents) to Restore at a time. [Default: 5000] (Restore Only)"
    echo -e "\t-t   Number of CPU threads to use when parsing data [Default: nProcs-1] (Backup Only)"
    echo -e "\t-a   Number of times to Attempt import before failing [Default: 3] (Restore/Import-Only)"
    echo -e "\t-s   Start at this specific split filename (Restore/Import-Only)"
    echo -e "\t-c   Create DB on demand, if they are not listed."
    echo -e "\t-q   Run in quiet mode. Suppress output, except for errors and warnings."
    echo -e "\t-z   Compress output file (Backup Only)"
    echo -e "\t-T   Add datetime stamp to output file name (Backup Only)"
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
    echo -e "\t Daniele Bailo    (bailo.daniele@gmail.com)"
    echo -e "\t Darren Gibbard   (dalgibbard@gmail.com)"
    echo -e "\t Maximilian Huber (maximilian.huber@tngtech.com)"
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
    KBavail=$(df -P -k ${stripdir} | tail -n 1 | awk '{print$4}' | $sed_cmd -e 's/K$//')

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
import_only=false
no_transform=false
import_delay=0
port=5984
OPTIND=1
lines=5000
attempts=3
createDBsOnDemand=false
verboseMode=true
compress=false
timestamp=false
start_at_file=""

while getopts ":h?H:d:f:u:p:P:l:t:s:a:D:c?q?z?T?V?b?B?r?R?i?I?n?N?" opt; do
    case "$opt" in
        h) usage;;
        b|B) backup=true ;;
        r|R) restore=true ;;
        i|I) import_only=true ;;
        n|N) no_transform=true ;;
        D) import_delay="${OPTARG}" ;;
        H) url="$OPTARG" ;;
        d) db_name="$OPTARG" ;;
        f) file_name="$OPTARG" ;;
        u) username="${OPTARG}";;
        p) password="${OPTARG}";;
        P) port="${OPTARG}";;
        l) lines="${OPTARG}" ;;
        t) threads="${OPTARG}" ;;
        a) attempts="${OPTARG}";;
        s) start_at_file="${OPTARG}";;
        c) createDBsOnDemand=true;;
        q) verboseMode=false;;
        z) compress=true;;
        T) timestamp=true;;
        V) scriptversion;;
        :) echo "... ERROR: Option \"-${OPTARG}\" requires an argument"; usage ;;
        *|\?) echo "... ERROR: Unknown Option \"-${OPTARG}\""; usage;;
    esac
done

# If quiet option: Setup echo mode and curl '--silent' opt
if [ "$verboseMode" = true ]; then
  curlSilentOpt=""
  echoVerbose=true
else
  curlSilentOpt="--silent"
  echoVerbose=false
fi

# Trap unexpected extra args
shift $((OPTIND-1))
[ "$1" = "--" ] && shift
if [ ! "x$@" = "x" ]; then
    echo "... ERROR: Unknown Option \"$@\""
    usage
fi

# Handle invalid backup/restore/import_only states:
mode_count=0
[ $backup = true ] && (( mode_count++ ))
[ $restore = true ] && (( mode_count++ ))
[ $import_only = true ] && (( mode_count++ ))

if [ $mode_count -gt 1 ]; then
    echo "... ERROR: Cannot pass multiple mode flags (-b, -r, -i). Choose one."
    usage
elif [ $mode_count -eq 0 ]; then
    echo "... ERROR: Missing argument '-b' (Backup), '-r' (Restore), or '-i' (Import-Only)"
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
file_name_orig=$file_name

# Get OS TYPE (Linux for Linux, Darwin for MacOSX)
os_type=`uname -s`

# Pick sed or gsed
if [ "$os_type" = "FreeBSD" ]||[ "$os_type" = "Darwin" ]; then
    sed_cmd="gsed";
else
    sed_cmd="sed";
fi
## Make sure it's installed
echo | $sed_cmd 's/a//' >/dev/null 2>&1 
if [ ! $? = 0 ]; then
    echo "... ERROR: please install $sed_cmd (gnu-sed) and ensure it is in your path"
    exit 1
fi

# Validate thread count
## If we're on a Mac, use sysctl
if [ "$os_type" = "Darwin" ]; then
    cores=`sysctl -n hw.ncpu`
## If we're on FreeBSD, use sysctl
elif [ "$os_type" = "FreeBSD" ]; then
    cores=`sysctl kern.smp.cpus | awk -F ": " '{print $2}'`;
## Check if nproc available- set cores=1 if not
elif ! type nproc >/dev/null; then
    cores=1
## Otherwise use nproc
else
    cores=`nproc`
fi
if [ ! "x$threads" = "x" ]; then
    if [ $threads -gt $cores ]; then
        echo "... WARN: Thread setting of $threads is more than CPU count. Setting to $cores"
        threads=$cores
    else
        $echoVerbose && echo "... INFO: Setting parser threads to $threads"
    fi
else
    threads=`expr $cores - 1`
fi

# Validate Attempts, set to no-retry if zero/invalid.
case $attempts in
    ''|0|*[!0-9]*) echo "... WARN: Retry Attempt value of \"$attempts\" is invalid. Disabling Retry-on-Error."; attempts=1 ;;
    *) true ;;
esac

## Manage the passing of http/https for $url:
# Note; if the user wants to use 'https://' on a non-443 port they must specify it exclusively in the '-H <HOSTNAME>' arg.
if [ ! "`echo $url | grep -c http`" = 1 ]; then
    if [ "$port" == "443" ]; then
        url="https://$url";
    else
        url="http://$url";
    fi
fi

# Manage the addition of port
# If a port isn't already on our URL...
if [ ! "`echo $url | egrep -c ":[0-9]*$"`" = "1" ]; then
    # add it.
    url="$url:$port"
fi	

# Check for empty user/pass and try reading in from Envvars
if [ "x$username" = "x" ]; then
    username="$COUCHDB_USER"
fi
if [ "x$password" = "x" ]; then
    password="$COUCHDB_PASS"
fi

## Manage the addition of user+pass if needed:
# Ensure, if one is set, both are set.
if [ ! "x${username}" = "x" ]; then
    if [ "x${password}" = "x" ]; then
        echo "... ERROR: Password cannot be blank, if username is specified."
        usage
    fi
elif [ ! "x${password}" = "x" ]; then
    if [ "x${username}" = "x" ]; then
        echo "... ERROR: Username cannot be blank, if password is specified."
        usage
    fi
fi

# Check for sed option
sed_edit_in_place='-i.sedtmp'
if [ "$os_type" = "Darwin" ]; then
    sed_regexp_option='E'
else
    sed_regexp_option='r'
fi
# Allow for self-signed/invalid certs if method is HTTPS:
if [ "`echo $url | grep -ic "^https://"`" = "1" ]; then
	curlopt="-k"
fi

if [ ! "x${username}" = "x" ]&&[ ! "x${password}" = "x" ]; then
    curlopt="${curlopt} -u ${username}:${password}"
fi

## Check for curl
curl --version >/dev/null 2>&1 || ( echo "... ERROR: This script requires 'curl' to be present."; exit 1 )

# Check for tr
echo | tr -d "" >/dev/null 2>&1 || ( echo "... ERROR: This script requires 'tr' to be present."; exit 1 )

##### SETUP OUR LARGE VARS FOR SPLIT PROCESSING (due to limitations in split on Darwin/BSD)
AZ2="`echo {a..z}{a..z}`"
AZ3="`echo {a..z}{a..z}{a..z}`"

### If user selected BACKUP, run the following code:
if [ $backup = true ]&&[ $restore = false ]; then
    #################################################################
    ##################### BACKUP START ##############################
    #################################################################

    # If -T (timestamp) option, append datetime stamp ("-YYYYMMDD-hhmmss") before file extension
    if [ "$timestamp" = true ]; then
      datetime=`date "+%Y%m%d-%H%M%S"`						# Format: YYYYMMDD-hhmmss
      # Check for file_name extension, if so add the timestamp before it
      if [[ $file_name =~ \.[a-zA-Z0-9][a-zA-Z0-9_]* ]]; then
        file_name_ext=` echo "$file_name" | $sed_cmd 's/.*\.//'`		# Get text after last '.'
        file_name_base=`echo "$file_name" | $sed_cmd "s/\.${file_name_ext}$//"`	# file_name without '.' & extension
        file_name="$file_name_base-$datetime.$file_name_ext"
      else # Otherwise add timestamp to the end of file_name
        file_name="$file_name-$datetime"
      fi
    fi
    $echoVerbose && echo "... INFO: Output file ${file_name}"

    # Check if output already exists:
    if [ -f ${file_name} ]; then
        echo "... ERROR: Output file ${file_name} already exists."
        exit 1
    fi

    # Grab our data from couchdb
    curl ${curlSilentOpt} ${curlopt} -X GET "$url/$db_name/_all_docs?include_docs=true&attachments=true" -o ${file_name}
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
    if grep -qU $'\x0d' $file_name; then
        $echoVerbose && echo "... INFO: File may contain Windows carridge returns- converting..."
        filesize=$(du -P -k ${file_name} | awk '{print$1}')
        checkdiskspace "${file_name}" $filesize
        tr -d '\r' < ${file_name} > ${file_name}.tmp
        if [ $? = 0 ]; then
            mv ${file_name}.tmp ${file_name}
            if [ $? = 0 ]; then
                $echoVerbose && echo "... INFO: Completed successfully."
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
    $echoVerbose && echo "... INFO: Amending file to make it suitable for Import."
    $echoVerbose && echo "... INFO: Stage 1 - Document filtering"

    # If the input file is larger than 250MB, multi-thread the parsing:
    if [ $(du -P -k ${file_name} | awk '{print$1}') -ge 256000 ]&&[ ! $threads -le 1 ]; then
        filesize=$(du -P -k ${file_name} | awk '{print$1}')
        KBreduction=$(($((`wc -l ${file_name} | awk '{print$1}'` * 80)) / 1024))
        filesize=`expr $filesize + $(expr $filesize - $KBreduction)`
        checkdiskspace "${file_name}" $filesize
        $echoVerbose && echo "... INFO: Multi-Threaded Parsing Enabled."
        if [ -f ${file_name}.thread000000 ]; then
            echo "... ERROR: Split files \"${file_name}.thread*\" already present. Please remove before continuing."
            exit 1
        elif [ -f ${file_name}.tmp ]; then
            echo "... ERROR: Tempfile ${file_name}.tmp already present. Please remove before continuing."
            exit 1
        fi

        ### SPLIT INTO THREADS
        split_cal=$(( $((`wc -l ${file_name} | awk '{print$1}'` / $threads)) + $threads ))
        #split --numeric-suffixes --suffix-length=6 -l ${split_cal} ${file_name} ${file_name}.thread
        split -a 2 -l ${split_cal} ${file_name} ${file_name}.thread
        if [ ! "$?" = "0" ]; then
            echo "... ERROR: Unable to create split files."
            exit 1
        fi

        # Capture if someone happens to breach the defined limits of AZ2 var. If this happens, we'll need to switch it out for AZ3 ...
        if [[ $threads -gt 650 ]]; then
            echo "Whoops- we hit a maximum limit here... \$AZ2 only allows for a maximum of 650 cores..."
            exit 1
        fi

        count=0
        for suffix in ${AZ2}; do
            (( count++ ))
            if [[ $count -gt $threads ]]; then
                break
            fi
            PADNAME="${file_name}.thread${suffix}"
            $sed_cmd ${sed_edit_in_place} 's/{"id".*,"doc"://g' ${PADNAME} &
        done
        wait
        count=0
        for suffix in ${AZ2}; do
            (( count++ ))
            if [[ $count -gt $threads ]]; then
                break
            fi
            PADNAME="${file_name}.thread${suffix}"
            cat ${PADNAME} >> ${file_name}.tmp
            rm -f ${PADNAME} ${PADNAME}.sedtmp
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
        filesize=$(du -P -k ${file_name} | awk '{print$1}')
        filesize=`expr $filesize - $KBreduction`
        checkdiskspace "${file_name}" $filesize
        $sed_cmd ${sed_edit_in_place} 's/{"id".*,"doc"://g' $file_name && rm -f ${file_name}.sedtmp
        if [ ! $? = 0 ];then
            echo "Stage failed."
            exit 1
        fi
    fi

    $echoVerbose && echo "... INFO: Stage 2 - Duplicate curly brace removal"
    # Approx 1Byte per line removed
    KBreduction=$((`wc -l ${file_name} | awk '{print$1}'` / 1024))
    filesize=$(du -P -k ${file_name} | awk '{print$1}')
    filesize=`expr $filesize - $KBreduction`
    checkdiskspace "${file_name}" $filesize
    $sed_cmd ${sed_edit_in_place} 's/}},$/},/g' ${file_name} && rm -f ${file_name}.sedtmp
    if [ ! $? = 0 ];then
        echo "Stage failed."
        exit 1
    fi
    $echoVerbose && echo "... INFO: Stage 3 - Header Correction"
    filesize=$(du -P -k ${file_name} | awk '{print$1}')
    checkdiskspace "${file_name}" $filesize
    $sed_cmd ${sed_edit_in_place} '1s/^.*/{"new_edits":false,"docs":[/' ${file_name} && rm -f ${file_name}.sedtmp
    if [ ! $? = 0 ];then
        echo "Stage failed."
        exit 1
    fi
    $echoVerbose && echo "... INFO: Stage 4 - Final document line correction"
    filesize=$(du -P -k ${file_name} | awk '{print$1}')
    checkdiskspace "${file_name}" $filesize
    $sed_cmd ${sed_edit_in_place} 's/}}$/}/g' ${file_name} && rm -f ${file_name}.sedtmp
    if [ ! $? = 0 ];then
        echo "Stage failed."
        exit 1
    fi

    # If -z (compress) option then compress output file
    if [ "$compress" = true ]; then
      $echoVerbose && echo "... INFO: Stage 5 - File compression"
      gzip $file_name
      file_name="$file_name.gz"
    fi

    $echoVerbose && echo "... INFO: Export completed successfully. File available at: ${file_name}"
    sync
    exit 0

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

    $echoVerbose && echo "... INFO: Checking for database"
    attemptcount=0
    A=0
    until [ $A = 1 ]; do
        (( attemptcount++ ))
        existing_dbs=$(curl $curlSilentOpt $curlopt -X GET "${url}/_all_dbs")
        if [ ! $? = 0 ]; then
            if [ $attemptcount = $attempts ]; then
                echo "... ERROR: Curl failed to get the list of databases - Stopping"
                exit 1
            else
                echo "... WARN: Curl failed to get the list of databases - Attempt ${attemptcount}/${attempts}. Retrying..."
                sleep 1
            fi
        else
            A=1
        fi
    done
    if [[ ! "$existing_dbs" = "["*"]" ]]; then
        echo "... WARN: Curl failed to get the list of databases - Continuing"
        if [ "x$existing_dbs" = "x" ]; then
            echo "... WARN: Curl just returned: $existing_dbs"
        fi
    elif [[ ! "$existing_dbs" = *"\"${db_name}\""* ]]; then
        # database was not listed as existing databasa
        if [ $createDBsOnDemand = true ]; then
            attemptcount=0
            A=0
            until [ $A = 1 ]; do
                (( attemptcount++ ))
                curl $curlSilentOpt $curlopt -X PUT "${url}/${db_name}" -o tmp.out
                # If curl threw an error:
                if [ ! $? = 0 ]; then
                    if [ $attemptcount = $attempts ]; then
                        echo "... ERROR: Curl failed to create the database ${db_name} - Stopping"
                        if [ -f tmp.out ]; then
                            echo -n "... ERROR: Error message was:   "
                            cat tmp.out
                        else
                            echo ".. ERROR: See above for any errors"
                        fi
                        exit 1
                    else
                        echo "... WARN: Curl failed to create the database ${db_name} - Attempt ${attemptcount}/${attempts}. Retrying..."
                        sleep 1
                    fi
                # If curl was happy, but CouchDB returned an error in the return JSON:
                elif [ ! "`head -n 1 tmp.out | grep -c '^{"error":'`" = 0 ]; then
                    if [ $attemptcount = $attempts ]; then
                        echo "... ERROR: CouchDB Reported: `head -n 1 tmp.out`"
                        exit 1
                    else
                        echo "... WARN: CouchDB Reported an error during db creation - Attempt ${attemptcount}/${attempts} - Retrying..."
                        sleep 1
                    fi
                # Otherwise, if everything went well, delete our temp files.
                else
                    rm tmp.out
                    A=1
                fi
            done
        else
            echo "... ERROR: corresponding database ${db_name} not yet created - Stopping"
            $echoVerbose && echo "... HINT: you could add the -c flag to create the database automatically"
            exit 1
        fi
    fi

    ## Stop bash mangling wildcard...
    set -o noglob
    # Manage Design Documents as a priority, and remove them from the main import job
    $echoVerbose && echo "... INFO: Checking for Design documents"
    # Find all _design docs, put them into another file
    design_file_name=${file_name}-design
    grep '^{"_id":"_design' ${file_name} > ${design_file_name}

    # Count the design file (if it even exists)
    DESIGNS="`wc -l ${design_file_name} 2>/dev/null | awk '{print$1}'`"
    # If there's no design docs for import...
    if [ "x$DESIGNS" = "x" ]||[ "$DESIGNS" = "0" ]; then 
        # Cleanup any null files
        rm -f ${design_file_name} 2>/dev/null
        $echoVerbose && echo "... INFO: No Design Documents found for import."
    else
        $echoVerbose && echo "... INFO: Duplicating original file for alteration"
        # Duplicate the original DB file, so we don't mangle the user's input file:
        filesize=$(du -P -k ${file_name} | awk '{print$1}')
        checkdiskspace "${file_name}" $filesize
        cp -f ${file_name}{,-nodesign}
        # Re-set file_name to be our new file.
        file_name=${file_name}-nodesign
        # Remove these design docs from (our new) main file.
        $echoVerbose && echo "... INFO: Stripping _design elements from regular documents"
        checkdiskspace "${file_name}" $filesize
        $sed_cmd ${sed_edit_in_place} '/^{"_id":"_design/d' ${file_name} && rm -f ${file_name}.sedtmp
        # Remove the final document's trailing comma
        $echoVerbose && echo "... INFO: Fixing end document"
        line=$(expr `wc -l ${file_name} | awk '{print$1}'` - 1)
        filesize=$(du -P -k ${file_name} | awk '{print$1}')
        checkdiskspace "${file_name}" $filesize
        $sed_cmd ${sed_edit_in_place} "${line}s/,$//" ${file_name} && rm -f ${file_name}.sedtmp

        $echoVerbose && echo "... INFO: Inserting Design documents"
        designcount=0
        # For each design doc...
        while IFS="" read -r; do
            line="${REPLY}"
            # Split the ID out for use as the import URL path
            URLPATH=$(echo $line | awk -F'"' '{print$4}')
            # Scrap the ID and Rev from the main data, as well as any trailing ','
            echo "${line}" | $sed_cmd -${sed_regexp_option}e "s@^\{\"_id\":\"${URLPATH}\",\"_rev\":\"[0-9]*-[0-9a-zA-Z_\-]*\",@\{@" | $sed_cmd -e 's/,$//' > ${design_file_name}.${designcount}
            # Fix Windows CRLF
            if grep -qU $'\x0d' ${design_file_name}.${designcount}; then
                $echoVerbose && echo "... INFO: File contains Windows carridge returns- converting..."
                filesize=$(du -P -k ${design_file_name}.${designcount} | awk '{print$1}')
                checkdiskspace "${file_name}" $filesize
                tr -d '\r' < ${design_file_name}.${designcount} > ${design_file_name}.${designcount}.tmp
                if [ $? = 0 ]; then
                    mv ${design_file_name}.${designcount}.tmp ${design_file_name}.${designcount}
                    if [ $? = 0 ]; then
                        $echoVerbose && echo "... INFO: Completed successfully."
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
            A=0
            attemptcount=0
            until [ $A = 1 ]; do
                (( attemptcount++ ))
                curl $curlSilentOpt ${curlopt} -T ${design_file_name}.${designcount} -X PUT "${url}/${db_name}/${URLPATH}" -H 'Content-Type: application/json' -o ${design_file_name}.out.${designcount}
                # If curl threw an error:
                if [ ! $? = 0 ]; then
                     if [ $attemptcount = $attempts ]; then
                         echo "... ERROR: Curl failed trying to restore ${design_file_name}.${designcount} - Stopping"
                         exit 1
                     else
                         echo "... WARN: Import of ${design_file_name}.${designcount} failed - Attempt ${attemptcount}/${attempts}. Retrying..."
                         sleep 1
                     fi
                # If curl was happy, but CouchDB returned an error in the return JSON:
                elif [ ! "`head -n 1 ${design_file_name}.out.${designcount} | grep -c '^{"error":'`" = 0 ]; then
                     if [ $attemptcount = $attempts ]; then
                         echo "... ERROR: CouchDB Reported: `head -n 1 ${design_file_name}.out.${designcount}`"
                         exit 1
                     else
                         echo "... WARN: CouchDB Reported an error during import - Attempt ${attemptcount}/${attempts} - Retrying..."
                         sleep 1
                     fi
                # Otherwise, if everything went well, delete our temp files.
                else
                     A=1
                     rm -f ${design_file_name}.out.${designcount}
                     rm -f ${design_file_name}.${designcount}
                fi
            done
            # Increase design count - mainly used for the INFO at the end.
            (( designcount++ ))
        # NOTE: This is where we insert the design lines exported from the main block
        done < <(cat ${design_file_name})
        $echoVerbose && echo "... INFO: Successfully imported ${designcount} Design Documents"
    fi
    set +o noglob

    # If the size of the file to import is less than our $lines size, don't worry about splitting
    if [ `wc -l $file_name | awk '{print$1}'` -lt $lines ]; then
        $echoVerbose && echo "... INFO: Small dataset. Importing as a single file."
        A=0
        attemptcount=0
        until [ $A = 1 ]; do
            (( attemptcount++ ))
            curl $curlSilentOpt $curlopt -T $file_name -X POST "$url/$db_name/_bulk_docs" -H 'Content-Type: application/json' -o tmp.out
            if [ "`head -n 1 tmp.out | grep -c '^{"error":'`" -eq 0 ]; then
                $echoVerbose && echo "... INFO: Imported ${file_name_orig} Successfully."
                rm -f tmp.out
                rm -f ${file_name_orig}-design
                rm -f ${file_name_orig}-nodesign
                exit 0
            else
                if [ $attemptcount = $attempts ]; then
                    echo "... ERROR: Import of ${file_name_orig} failed."
                    if [ -f tmp.out ]; then
                        echo -n "... ERROR: Error message was:   "
                        cat tmp.out
                    else
                        echo ".. ERROR: See above for any errors"
                    fi
                    rm -f tmp.out
                    exit 1
                else
                    echo "... WARN: Import of ${file_name_orig} failed - Attempt ${attemptcount}/${attempts} - Retrying..."
                    sleep 1
                fi
            fi
        done
    # Otherwise, it's a large import that requires bulk insertion.
    else
        $echoVerbose && echo "... INFO: Block import set to ${lines} lines."
        if [ -f ${file_name}.splitaaa ]; then
            echo "... ERROR: Split files \"${file_name}.split*\" already present. Please remove before continuing."
            exit 1
        fi
        importlines=`cat ${file_name} | grep -c .`

        # Due to the file limit imposed by the pre-calculated AZ3 variable, max split files is 15600 (alpha x 3positions)
        if [[ `expr ${importlines} / ${lines}` -gt 15600 ]]; then
            echo "... ERROR: Pre-processed split variable limit of 15600 files reached."
            echo "           Please increase the '-l' parameter (Currently: $lines) and try again."
            exit 1
        fi

        $echoVerbose && echo "... INFO: Generating files to import"
        filesize=$(du -P -k ${file_name} | awk '{print$1}')
        checkdiskspace "${file_name}" $filesize
        ### Split the file into many
        
        ${split_command_path} -a 3 -l ${lines} ${file_name} ${file_name}.split
        # using perl split above instead of this, which sometimes breaks lines across files
        # split -a 3 -l ${lines} ${file_name} ${file_name}.split
        if [ ! "$?" = "0" ]; then
            echo "... ERROR: Unable to create split files."
            exit 1
        fi
        HEADER="`head -n 1 $file_name`"
        FOOTER="`tail -n 1 $file_name`"

		actually_do_it=true
		
		if [ ! -z "$start_at_filename" ] ; then
			actually_do_it=false
		fi
		
        count=0
        for PADNUM in $AZ3; do
            PADNAME="${file_name}.split${PADNUM}"
            if [ ! -f ${PADNAME} ]; then
            	if ! $actually_do_it ; then
            	  echo "Looking for start file: $start_at_filename, scrolling past $PADNAME"
            	else
                  echo "... INFO: Import Cycle Completed."
                  break
                fi
            fi
            
            if [ ! -z "$start_at_filename" ] && [ $PADNAME = $start_at_filename ] ; then 
            	echo "Reached start file ${start_at_filename}"
            	actually_do_it=true;
            fi
            
            if $actually_do_it ; then
                echo "good to go now"
            else
                echo "Skipping ${PADNAME} because we are not yet at start file ${start_at_filename}"
            	continue
            fi

            if [ ! "`head -n 1 ${PADNAME}`" = "${HEADER}" ]; then
                $echoVerbose && echo "... INFO: Adding header to ${PADNAME}"
                filesize=$(du -P -k ${PADNAME} | awk '{print$1}')
                checkdiskspace "${PADNAME}" $filesize
                $sed_cmd ${sed_edit_in_place} "1i${HEADER}" ${PADNAME} && rm -f ${PADNAME}.sedtmp
            else
                $echoVerbose && echo "... INFO: Header already applied to ${PADNAME}"
            fi
            if [ ! "`tail -n 1 ${PADNAME}`" = "${FOOTER}" ]; then
                $echoVerbose && echo "... INFO: Adding footer to ${PADNAME}"
                filesize=$(du -P -k ${PADNAME} | awk '{print$1}')
                checkdiskspace "${PADNAME}" $filesize
                $sed_cmd ${sed_edit_in_place} '$s/,$//g' ${PADNAME} && rm -f ${PADNAME}.sedtmp
                echo "${FOOTER}" >> ${PADNAME}
            else
                $echoVerbose && echo "... INFO: Footer already applied to ${PADNAME}"
            fi

            $echoVerbose && echo "... INFO: Inserting ${PADNAME}"
            A=0
            attemptcount=0
            until [ $A = 1 ]; do
                (( attemptcount++ ))
                curl $curlSilentOpt $curlopt -T ${PADNAME} -X POST "$url/$db_name/_bulk_docs" -H 'Content-Type: application/json' -o tmp.out
                if [ ! $? = 0 ]; then
                    if [ $attemptcount = $attempts ]; then
                        echo "... ERROR: Curl failed trying to restore ${PADNAME} - Stopping"
                        exit 1
                    else
                        echo "... WARN: Failed to import ${PADNAME} - Attempt ${attemptcount}/${attempts} - Retrying..."
                        sleep 1
                    fi
                elif [ ! "`head -n 1 tmp.out | grep -c '^{"error":'`" = 0 ]; then
                    if [ $attemptcount = $attempts ]; then
                        echo "... ERROR: CouchDB Reported: `head -n 1 tmp.out`"
                        exit 1
                    else
                        echo "... WARN: CouchDB Reported and error during import - Attempt ${attemptcount}/${attempts} - Retrying..."
                        sleep 1
                    fi
                else
                    A=1
                    rm -f ${PADNAME}
                    rm -f tmp.out
                    (( count++ ))
                fi
            done

            $echoVerbose && echo "... INFO: Successfully Imported `expr ${count}` Files"
            A=1
            rm -f ${file_name_orig}-design
            rm -f ${file_name_orig}-nodesign
        done
    fi

### Else if user selected Import-Only mode:
elif [ $import_only = true ]; then
    #################################################################
    ##################### IMPORT-ONLY START ##########################
    #################################################################
    # This mode imports pre-existing split files without splitting or design doc handling.
    # Useful for distributing pre-split files to others for import.

    $echoVerbose && echo "... INFO: Running in IMPORT-ONLY mode"

    # Check for directory structure or flat files
    if ls -d "${file_name}.split_dir"* >/dev/null 2>&1; then
        $echoVerbose && echo "... INFO: Found directory structure: ${file_name}.split_dir*"
    elif [ -f "${file_name}.splitaaa" ]; then
        $echoVerbose && echo "... INFO: Found flat files: ${file_name}.split*"
    else
        echo "... ERROR: No split files found."
        echo "... ERROR: Expected directories like ${file_name}.split_dir0000/ or files like ${file_name}.splitaaa"
        exit 1
    fi

    $echoVerbose && echo "... INFO: Checking for database"
    attemptcount=0
    A=0
    until [ $A = 1 ]; do
        (( attemptcount++ ))
        existing_dbs=$(curl $curlSilentOpt $curlopt -X GET "${url}/_all_dbs")
        if [ ! $? = 0 ]; then
            if [ $attemptcount = $attempts ]; then
                echo "... ERROR: Curl failed to get the list of databases - Stopping"
                exit 1
            else
                echo "... WARN: Curl failed to get the list of databases - Attempt ${attemptcount}/${attempts}. Retrying..."
                sleep 1
            fi
        else
            A=1
        fi
    done
    if [[ ! "$existing_dbs" = "["*"]" ]]; then
        echo "... WARN: Curl failed to get the list of databases - Continuing"
        if [ "x$existing_dbs" = "x" ]; then
            echo "... WARN: Curl just returned: $existing_dbs"
        fi
    elif [[ ! "$existing_dbs" = *"\"${db_name}\""* ]]; then
        if [ $createDBsOnDemand = true ]; then
            attemptcount=0
            A=0
            until [ $A = 1 ]; do
                (( attemptcount++ ))
                curl $curlSilentOpt $curlopt -X PUT "${url}/${db_name}" -o tmp.out
                if [ ! $? = 0 ]; then
                    if [ $attemptcount = $attempts ]; then
                        echo "... ERROR: Curl failed to create the database ${db_name} - Stopping"
                        if [ -f tmp.out ]; then
                            echo -n "... ERROR: Error message was:   "
                            cat tmp.out
                        else
                            echo ".. ERROR: See above for any errors"
                        fi
                        exit 1
                    else
                        echo "... WARN: Curl failed to create the database ${db_name} - Attempt ${attemptcount}/${attempts}. Retrying..."
                        sleep 1
                    fi
                elif [ ! "`head -n 1 tmp.out | grep -c '^{"error":'`" = 0 ]; then
                    if [ $attemptcount = $attempts ]; then
                        echo "... ERROR: CouchDB Reported: `head -n 1 tmp.out`"
                        exit 1
                    else
                        echo "... WARN: CouchDB Reported an error during db creation - Attempt ${attemptcount}/${attempts} - Retrying..."
                        sleep 1
                    fi
                else
                    rm tmp.out
                    A=1
                fi
            done
        else
            echo "... ERROR: corresponding database ${db_name} not yet created - Stopping"
            $echoVerbose && echo "... HINT: you could add the -c flag to create the database automatically"
            exit 1
        fi
    fi

    # Handle -s (start_at_file) option
    actually_do_it=true
    if [ ! -z "$start_at_file" ]; then
        actually_do_it=false
    fi

    # Standard header/footer for CouchDB bulk import
    HEADER='{"new_edits":false,"docs":['
    FOOTER=']}'

    count=0
    
    # Build list of files to import
    # Check if using directory structure (new) or flat files (old)
    if ls -d "${file_name}.split_dir"* >/dev/null 2>&1; then
        # New directory structure: base.split_dir0000/, base.split_dir0001/, etc.
        $echoVerbose && echo "... INFO: Using directory structure"
        FILE_LIST=$(find "${file_name}.split_dir"* -name 'split*' -type f 2>/dev/null | sort)
    else
        # Old flat file structure: base.splitaaa, base.splitaab, etc.
        $echoVerbose && echo "... INFO: Using flat file structure"
        FILE_LIST=""
        for PADNUM in $AZ3; do
            PADNAME="${file_name}.split${PADNUM}"
            if [ -f "${PADNAME}" ]; then
                FILE_LIST="${FILE_LIST} ${PADNAME}"
            fi
        done
    fi
    
    # Count total files for progress
    TOTAL_FILES=$(echo "$FILE_LIST" | wc -w | tr -d ' ')
    $echoVerbose && echo "... INFO: Found ${TOTAL_FILES} files to import"
    
    for PADNAME in $FILE_LIST; do
        if [ ! -f "${PADNAME}" ]; then
            continue
        fi
        
        # Handle start_at_file (-s flag)
        if [ ! -z "$start_at_file" ] && [ "$PADNAME" = "$start_at_file" ]; then
            echo "... INFO: Reached start file ${start_at_file}"
            actually_do_it=true
        fi
        
        if ! $actually_do_it; then
            continue
        fi

        # Skip all transformations if -n flag is set
        if [ "$no_transform" = false ]; then
            # First, strip Windows carriage returns if present
            if grep -qU $'\x0d' ${PADNAME} 2>/dev/null; then
                $echoVerbose && echo "... INFO: Removing Windows carriage returns from ${PADNAME}"
                filesize=$(du -P -k ${PADNAME} | awk '{print$1}')
                checkdiskspace "${PADNAME}" $filesize
                tr -d '\r' < ${PADNAME} > ${PADNAME}.tmp && mv ${PADNAME}.tmp ${PADNAME}
            fi
            
            # Check if file needs transformation (raw CouchDB format vs processed)
            needs_transform=false
            needs_brace_fix=false
            
            # Detect raw format by checking for "doc":{ pattern (indicates wrapper needs stripping)
            if grep -q '"doc":{' ${PADNAME} 2>/dev/null; then
                needs_transform=true
            fi
            
            # Also check for }}, at end of line (indicates Stage 2 brace fix is needed for raw format)
            # Only trigger on lines that END with }}, which indicates raw wrapper, not valid nested JSON
            if grep -q '^{.*}},\s*$' ${PADNAME} 2>/dev/null; then
                needs_brace_fix=true
            fi
            
            if [ "$needs_transform" = true ]; then
                $echoVerbose && echo "... INFO: Transforming raw format in ${PADNAME}"
                filesize=$(du -P -k ${PADNAME} | awk '{print$1}')
                checkdiskspace "${PADNAME}" $filesize
                
                # Remove raw header line if present ({"total_rows":... or leftover from previous run)
                if grep -q '^{"total_rows":' ${PADNAME} 2>/dev/null; then
                    $echoVerbose && echo "... INFO:   Removing raw header line"
                    $sed_cmd ${sed_edit_in_place} '/^{"total_rows":/d' ${PADNAME} && rm -f ${PADNAME}.sedtmp
                fi
                
                # Stage 1: Strip {"id":...,"doc": wrapper from each document
                $echoVerbose && echo "... INFO:   Stage 1 - Stripping document wrapper"
                $sed_cmd ${sed_edit_in_place} 's/{"id".*,"doc"://g' ${PADNAME} && rm -f ${PADNAME}.sedtmp
                
                # Stage 2: Fix double closing braces }}, -> },
                $echoVerbose && echo "... INFO:   Stage 2 - Fixing double braces"
                $sed_cmd ${sed_edit_in_place} 's/}},$/},/g' ${PADNAME} && rm -f ${PADNAME}.sedtmp
                
                # Stage 4: Fix end brace on last document }} -> }
                $echoVerbose && echo "... INFO:   Stage 4 - Fixing end braces"
                $sed_cmd ${sed_edit_in_place} 's/}}$/}/g' ${PADNAME} && rm -f ${PADNAME}.sedtmp
                
            elif [ "$needs_brace_fix" = true ]; then
                # Partial transformation - wrapper stripped but braces not fixed
                $echoVerbose && echo "... INFO: Fixing braces in ${PADNAME}"
                filesize=$(du -P -k ${PADNAME} | awk '{print$1}')
                checkdiskspace "${PADNAME}" $filesize
                
                # Stage 2: Fix double closing braces }}, -> },
                $echoVerbose && echo "... INFO:   Stage 2 - Fixing double braces"
                $sed_cmd ${sed_edit_in_place} 's/}},$/},/g' ${PADNAME} && rm -f ${PADNAME}.sedtmp
                
                # Stage 4: Fix end brace on last document }} -> }
                $echoVerbose && echo "... INFO:   Stage 4 - Fixing end braces"
                $sed_cmd ${sed_edit_in_place} 's/}}$/}/g' ${PADNAME} && rm -f ${PADNAME}.sedtmp
            fi
            
            # Fix header if needed
            first_line=$(head -n 1 ${PADNAME})
            if [ ! "$first_line" = "${HEADER}" ]; then
                $echoVerbose && echo "... INFO: Adding header to ${PADNAME}"
                filesize=$(du -P -k ${PADNAME} | awk '{print$1}')
                checkdiskspace "${PADNAME}" $filesize
                # Insert header at beginning (don't replace - first line might be a document)
                $sed_cmd ${sed_edit_in_place} "1i${HEADER}" ${PADNAME} && rm -f ${PADNAME}.sedtmp
            fi
            
            # Fix footer if needed
            last_line=$(tail -n 1 ${PADNAME})
            if [ "$last_line" = "${FOOTER}" ]; then
                # Footer exists, but check if second-to-last line has trailing comma
                second_to_last=$(tail -n 2 ${PADNAME} | head -n 1)
                if [[ "$second_to_last" == *, ]]; then
                    $echoVerbose && echo "... INFO: Removing trailing comma before footer in ${PADNAME}"
                    filesize=$(du -P -k ${PADNAME} | awk '{print$1}')
                    checkdiskspace "${PADNAME}" $filesize
                    # Remove the trailing comma from second-to-last line
                    total_lines=$(wc -l < ${PADNAME})
                    target_line=$((total_lines - 1))
                    $sed_cmd ${sed_edit_in_place} "${target_line}s/,$//" ${PADNAME} && rm -f ${PADNAME}.sedtmp
                fi
            else
                $echoVerbose && echo "... INFO: Fixing footer in ${PADNAME}"
                filesize=$(du -P -k ${PADNAME} | awk '{print$1}')
                checkdiskspace "${PADNAME}" $filesize
                # Remove trailing comma from last line, then add footer
                $sed_cmd ${sed_edit_in_place} '$s/,$//' ${PADNAME} && rm -f ${PADNAME}.sedtmp
                echo "${FOOTER}" >> ${PADNAME}
            fi
        fi

        $echoVerbose && echo "... INFO: Importing ${PADNAME}"
        A=0
        attemptcount=0
        until [ $A = 1 ]; do
            (( attemptcount++ ))
            curl $curlSilentOpt $curlopt -T ${PADNAME} -X POST "$url/$db_name/_bulk_docs" -H 'Content-Type: application/json' -o tmp.out
            if [ ! $? = 0 ]; then
                if [ $attemptcount = $attempts ]; then
                    echo "... ERROR: Curl failed trying to import ${PADNAME} - Stopping"
                    echo "... INFO: Resume with: -i -s ${PADNAME}"
                    exit 1
                else
                    echo "... WARN: Failed to import ${PADNAME} - Attempt ${attemptcount}/${attempts} - Retrying..."
                    sleep 1
                fi
            elif [ ! "`head -n 1 tmp.out | grep -c '^{"error":'`" = 0 ]; then
                if [ $attemptcount = $attempts ]; then
                    echo "... ERROR: CouchDB Reported: `head -n 1 tmp.out`"
                    echo "... INFO: Resume with: -i -s ${PADNAME}"
                    exit 1
                else
                    echo "... WARN: CouchDB Reported an error during import - Attempt ${attemptcount}/${attempts} - Retrying..."
                    sleep 1
                fi
            else
                A=1
                rm -f tmp.out
                (( count++ ))
            fi
        done
        $echoVerbose && echo "... INFO: Successfully imported ${PADNAME} (${count}/${TOTAL_FILES})"
        
        # Delay between imports if specified
        if [ "$import_delay" -gt 0 ] 2>/dev/null; then
            $echoVerbose && echo "... INFO: Waiting ${import_delay} seconds before next import..."
            sleep ${import_delay}
        fi
    done

    $echoVerbose && echo "... INFO: Import-only completed. Total files imported: ${count}"
    exit 0
fi
