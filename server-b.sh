#!/bin/bash

# Define variables
SOURCE_DIR_A="/opt/vxflow/temp-files"
DEST_DIR_B="/opt/vxflow/temp-input-files"
FINAL_DIR_B="/opt/vxflow/input-files"
SERVER_A_SCR_PATH="/opt/vxflow/server-a.sh"
LOG_FILE="/var/log/server_b_file_transfer.log"
# SSH variables
SSH_KEY="/opt/.ssh/ubuntu-testing-key"
SSH_USER_ADDRESS="user@server_A"
SSH_PORT="22"
# Used for log messages
SERVER_A_ID="Server A"
SERVER_B_ID="Server B"

log_message() {
    local level="$1"
    local message="$2"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [$level] - $message" >> $LOG_FILE
}

# Remove files from the destination directory on Server B
remove_files_from_server_b() {
    log_message "INFO" "Removing all files from $(basename "$DEST_DIR_B")."
    rm -rf "$DEST_DIR_B/"* 2>/dev/null
}

# Check for the 'wait' file on Server A
check_wait_file() {
    log_message "INFO" "Checking for 'wait' file on $SERVER_A_ID."
    if ssh -i $SSH_KEY -p $SSH_PORT $SSH_USER_ADDRESS "[ -f ${SOURCE_DIR_A}/wait ]"; then
        log_message "INFO" "'wait' file detected on $SERVER_A_ID. Exiting script."
        exit 0
    fi
}

# Check for files available for transfer on Server A
check_files_on_server_a() {
    log_message "INFO" "Checking for files in $(basename "$SOURCE_DIR_A") on $SERVER_A_ID."
    FILE_LIST=$(ssh -i $SSH_KEY -p $SSH_PORT $SSH_USER_ADDRESS "ls -1 $SOURCE_DIR_A 2>/dev/null | grep -v '^wait$'")

    if [ -z "$FILE_LIST" ]; then
        log_message "INFO" "No files found in $(basename "$SOURCE_DIR_A") on $SERVER_A_ID."
        exit 0
    fi

    log_message "INFO" "Files available for transfer from $SERVER_A_ID."
}

# Read and delete checksum file after transfer
read_and_remove_checksum_file() {
    local checksum_file="$DEST_DIR_B/checksum"

    if [ -f "$checksum_file" ]; then
        log_message "INFO" "Reading checksum file at $checksum_file."
        CHECKSUM_VALUE=$(cat "$checksum_file")
        log_message "INFO" "Checksum value read: $CHECKSUM_VALUE."
        log_message "INFO" "Deleting checksum file from $(basename "$DEST_DIR_B")."
        rm -f "$checksum_file"
    else
        log_message "ERROR" "Checksum file not found in $(basename "$DEST_DIR_B"). Aborting transfer."
        trigger_checksum_recalculation
        exit 0
    fi
}

# Start file transfer from Server A to Server B
transfer_files_from_server_a_to_b() {
    log_message "INFO" "Starting file transfer from $SOURCE_DIR_A to $DEST_DIR_B."
    scp -i $SSH_KEY -P $SSH_PORT $SSH_USER_ADDRESS:"${SOURCE_DIR_A}/"* "$DEST_DIR_B/"
    if [ $? -eq 0 ]; then
        log_message "INFO" "The following files have been transferred from $SERVER_A_ID to $SERVER_B_ID:"
        for file in "$DEST_DIR_B/"*; do
            log_message "INFO" " - $(basename "$file")"
        done
    else
        log_message "ERROR" "File transfer failed."
        remove_files_from_server_b
        exit 1
    fi
}

# Verify the checksum of transferred files
verify_checksum() {
    log_message "INFO" "Calculating checksum for files in $DEST_DIR_B."

    # Get a sorted list of files and calculate checksum
    find "$DEST_DIR_B/" -type f -print0 | sort -z > /tmp/sorted_files_list_server_b
    DEST_CHECKSUM=$(tr '\0' '\n' < /tmp/sorted_files_list_server_b | xargs -d '\n' md5sum | cut -d ' ' -f 1 | md5sum | cut -d ' ' -f 1)

    log_message "INFO" "Calculated checksum for $SERVER_B_ID files: $DEST_CHECKSUM."

    if [ "$CHECKSUM_VALUE" != "$DEST_CHECKSUM" ]; then
        log_message "ERROR" "Checksum mismatch. Triggering checksum recalculation on $SERVER_A_ID."
        trigger_checksum_recalculation
        exit 0
    fi
    log_message "INFO" "Checksum verification passed. Files are consistent."
}

# Trigger checksum recalculation on Server A by calling manage_files.sh with recalculate_checksum parameter
trigger_checksum_recalculation() {
    log_message "INFO" "Starting checksum recalculation process on $SERVER_A_ID."

    # Trigger the script on Server A to recalculate the checksum
    ssh -i $SSH_KEY -p $SSH_PORT $SSH_USER_ADDRESS "$SERVER_A_SCR_PATH recalculate_checksum"
    cleanup_server_b
    log_message "INFO" "Checksum recalculation triggered on $SERVER_A_ID. Exiting the script now."
}

# Move files to final directory
move_to_final_directory() {
    log_message "INFO" "Moving files from $(basename "$DEST_DIR_B") to final destination directory on $SERVER_B_ID."
    mv "$DEST_DIR_B/"* "$FINAL_DIR_B/"
    if [ $? -eq 0 ]; then
        log_message "INFO" "Files successfully moved to $(basename "$FINAL_DIR_B")."
    else
        log_message "ERROR" "Failed to move files to $FINAL_DIR_B."
        exit 1
    fi
}

# Clean up temporary files on Server A
cleanup_server_a() {
    log_message "INFO" "Cleaning up files from $SERVER_A_ID temp directory."
    ssh -i $SSH_KEY -p $SSH_PORT $SSH_USER_ADDRESS "rm -f ${SOURCE_DIR_A}/*"
    log_message "INFO" "Cleanup on $SERVER_A_ID completed."
}

# Clean up temporary files from Server B
cleanup_server_b() {
    log_message "INFO" "Cleaning up temporary files from $(basename "$DEST_DIR_B")."
    rm -rf "$DEST_DIR_B/"* 2>/dev/null
    log_message "INFO" "Cleanup on $SERVER_B_ID completed."
}

# Ensure log file exists
if [ ! -f "$LOG_FILE" ]; then
    touch $LOG_FILE
    chmod 644 $LOG_FILE
fi

log_message "INFO" "$SERVER_B_ID transfer script started."

# Wait 3 seconds for 'wait' file to be created
sleep 3

# Check for 'wait' file on Server A
check_wait_file

# Check for files to transfer from Server A
check_files_on_server_a

# Transfer files from Server A to Server B
transfer_files_from_server_a_to_b

# Read and delete checksum file from Server B
read_and_remove_checksum_file

# Verify checksum for transferred files
verify_checksum

# Move verified files to final directory
move_to_final_directory

# Clean up temporary files from Server A
cleanup_server_a

log_message "INFO" "File transfer and integrity verification completed successfully."
exit 0
