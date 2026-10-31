verify_target_checksum() {
    local target_file="/system/lib64/libinputreader.so"
    local expected_md5="5812b8a34680016771cd7ee882606862"

    if [ ! -f "$target_file" ]; then
        return 1
    fi

    local current_md5
    current_md5=$(md5sum "$target_file" 2>/dev/null | awk '{print $1}' | tr '[:upper:]' '[:lower:]')

    [ "$current_md5" = "$expected_md5" ]
}
