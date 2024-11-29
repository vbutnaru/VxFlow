#!/bin/bash

# Define variables
SOURCE_DIR_A="/opt/vxflow/received-files"
DEST_DIR_A="/opt/vxflow/temp-files"
LOG_FILE="/var/log/manage_files.log"
# Used for log messages
SERVER_A_ID="Server A"
SERVER_B_ID="Server B"


log_message() {
    local level="$1"
    local message="$2"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [$level] - $message" >> $LOG_FILE
}

# Create the 'wait' file to signal Server B to pause
create_wait_file() {
    touch "$DEST_DIR_A/wait"
    log_message "INFO" "Created 'wait' file in $(basename "$DEST_DIR_A") directory. The script on $SERVER_B_ID will wait until files are fully moved."
}

# Remove the 'wait' file when the file move operation is complete
remove_wait_file() {
    rm -f "$DEST_DIR_A/wait"
    log_message "INFO" "Removed 'wait' file from $(basename "$DEST_DIR_A") directory. The script on $SERVER_B_ID can resume file transfer."
}

# Remove the 'checksum' file when an error occurs
remove_checksum_file() {
    rm -f "$DEST_DIR_A/checksum"
    log_message "INFO" "Removed 'checksum' file from $(basename "$DEST_DIR_A")."
}

# Create checksum file for all files in the source directory
create_checksum_file() {
    CHECKSUM_FILE="$DEST_DIR_A/checksum"
    log_message "INFO" "Generating checksum for all files in $(basename "$DEST_DIR_A") (ignoring 'wait' file) and storing it in $(basename "$CHECKSUM_FILE") file."

    # Get a sorted list of files
    find "$DEST_DIR_A" -type f ! -name "wait" -print0 | sort -z > /tmp/sorted_files_list

    # Generate checksum based on sorted list
    tr '\0' '\n' < /tmp/sorted_files_list | xargs -d '\n' md5sum | cut -d ' ' -f 1 | md5sum | cut -d ' ' -f 1 > "$CHECKSUM_FILE"

    if [ $? -eq 0 ]; then
        log_message "INFO" "Checksum file successfully created at $CHECKSUM_FILE."
    else
        log_message "ERROR" "Failed to generate checksum file at $CHECKSUM_FILE."
    fi
}

# Function to recalculate checksum when requested
recalculate_checksum() {
    log_message "INFO" "Starting checksum recalculation process."
    create_wait_file

    if [ -f "$DEST_DIR_A/checksum" ]; then
        remove_checksum_file
    fi

    create_checksum_file
    remove_wait_file
    log_message "INFO" "Checksum recalculation process completed."
}

# Ensure log file exists
if [ ! -f "$LOG_FILE" ]; then
    touch $LOG_FILE
    chmod 644 $LOG_FILE
fi

# Check if the script is executed to recalculate the checksum of files from DEST_DIR_A
if [ "$1" == "recalculate_checksum" ]; then
    recalculate_checksum
    exit 0
fi

# Ensure source and destination directories exist
if [ ! -d "$SOURCE_DIR_A" ] || [ ! -d "$DEST_DIR_A" ]; then
    log_message "ERROR" "Either source directory $SOURCE_DIR_A or destination directory $DEST_DIR_A does not exist. Exiting."
    exit 1
fi

# Check if source directory is empty
if [ ! "$(ls -A $SOURCE_DIR_A 2>/dev/null)" ]; then
    log_message "INFO" "Source directory is empty. No files to move."
    exit 0
fi

# Check if destination directory is empty
if [ "$(ls -A $DEST_DIR_A 2>/dev/null)" ]; then
    log_message "INFO" "Destination directory is not empty. Skipping file move."
else
    create_wait_file
    ERROR_MSG=$(mv "${SOURCE_DIR_A}/"* "$DEST_DIR_A" 2>&1)
    
    if [ $? -eq 0 ]; then
        log_message "INFO" "The following files have been successfully moved from $(basename "$SOURCE_DIR_A") to $(basename "$DEST_DIR_A"):"
        for file in "$DEST_DIR_A/"*; do
            log_message "INFO" " - $(basename "$file")"
        done

        create_checksum_file
        remove_wait_file
    else
        log_message "ERROR" "Failed to move files from $SOURCE_DIR_A to $DEST_DIR_A. Error: $ERROR_MSG"
        remove_wait_file
        remove_checksum_file
    fi
fi

