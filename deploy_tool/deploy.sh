#!/bin/bash
set -euo pipefail
version=$1
task=$2

debug_mode=true  

function log() {
    if [ "$debug_mode" = true ]; then
        echo "[DEBUG] $1"
    fi
}

# Define common regex patterns
pattern="(8|9|10|11|12).[0-9].[0-9]{1,2}.[0-9]{4}-[a-z0-9]{7}"
pattern_engine="CUBRID-${pattern}-Linux.x86_64.(rpm|sh|tar.gz)|CUBRID-Windows-x64-${pattern}.(zip|msi)|cubrid-${pattern}.(zip|tar.gz)"
pattern_jdbc="JDBC-*"
pattern_cci="CUBRID-CCI-*" 

# Use variables for common directory paths
build_drop_dir="/home/dist/data/CUBRID_Engine/nightly/daily_build/${version}/drop"
engine_dir=/home/dist/data/CUBRID_Engine
driver_dir=/home/dist/data/CUBRID_Drivers
jdbc_dir=${driver_dir}/JDBC_Driver
cci_dir=${driver_dir}/CCI_Driver
target_dir=
#############################################

function print_help() {
	echo
    echo "Usage: bash $0 version {deploy_engine|deploy_jdbc|deploy_cci|display_results}"
    echo "Example: bash $0 11.4.0.1142-earfsd deploy_engine"
	echo
}

function parse_version() {
	log "parse_version start"
    IFS='.' read -r major minor patch build <<< "$(echo $version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')"
	log "Parsed version: major=$major, minor=$minor, patch=$patch, build=$build"
}

# Improve error handling in functions
function copy_files() {
    local src_dir=$1
    local dest_dir=$2
    local files=("${@:3}")
    for file in "${files[@]}"; do
        if [ ! -f "${src_dir}/${file}" ]; then
            echo "Error: ${src_dir}/${file} does not exist"
            exit 1
        else
            cp -r "${src_dir}/${file}" "${dest_dir}/" || { echo "Failed to copy $file"; exit 1; }
        fi
        log "Copied ${file} from ${src_dir} to ${dest_dir}"
    done
}

# make_symbolic_links "${src_dir}" "${target_dir}" "${version}" "${files[@]}"
function make_symbolic_links() {
    local src_dir=$1
    local target_dir=$2
    local version=$3
    local files=("${@:4}")
    local new_version=$(echo "$version" | awk -F'.' '{print $1"."$2"-latest"}')

    if [ ! -d "${target_dir}" ]; then
        echo "Error: Target directory ${target_dir} does not exist."
        exit 1
    fi

    cd "${target_dir}" || { echo "Error: Failed to change directory to ${target_dir}"; exit 1; }

    for file in "${files[@]}"; do
        if [ ! -e "${src_dir}/${file}" ]; then
            echo "Error: Source file ${src_dir}/${file} does not exist."
            exit 1
        fi
        local link_name=$(echo "$file" | sed "s/${version}/${new_version}/")
        ln -Tfs "${src_dir}/${file}" "${link_name}" || { echo "Error: Failed to create symbolic link ${link_name}"; exit 1; }
        log "Created symbolic link ${link_name} -> ${src_dir}/${file}"
    done
}

# Function to handle version comparison and extraction
function extract_version_components() {
    local version=$1
    echo "$version" | awk -F'[-.]' '{print $1,$2,$3,$4}'
}

function get_former_version() {
    local in_version=$1
    local in_type=$2
    local dir_path=$(eval echo \${${in_type}_dir})
    local patt=""

    read major minor patch build <<< $(extract_version_components "$in_version")
    log "Extracted version components: major=$major, minor=$minor, patch=$patch, build=$build"

    if [ "$in_type" == "jdbc" ]; then
        patt="[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"
        local versions_list=$(find "$dir_path" -type f | grep -Eo "$patt" | sort -Vu)
    else
        patt="[0-9]+\.[0-9]+\.[0-9]+"
        local versions_list=$(find "$dir_path" -type d | grep -Eo "$patt" | sort -Vu)
    fi

    local previous_version=$(echo "$versions_list" | grep -B1 "$major.$minor.$patch" | head -n1)

    if [ -z "$previous_version" ]; then
        log "No previous version found for major=$major, minor=$minor, patch=$patch"
        former_version=""
        release_type="unknown"
        return
    fi

    read prev_major prev_minor prev_patch prev_build <<< $(extract_version_components "$previous_version")
    log "Extracted previous version components: prev_major=$prev_major, prev_minor=$prev_minor, prev_patch=$prev_patch, prev_build=$prev_build"
    
    if [ "$major" -ne "$prev_major" ]; then
        release_type="major"
    elif [ "$minor" -ne "$prev_minor" ]; then
        release_type="minor"
    elif [ "$patch" -ne "$prev_patch" ]; then
        release_type="patch"
    else
        release_type="build"
    fi

    log "Former version: $previous_version, Release type: $release_type"
    former_version="$previous_version"
}

function deploy_engine() {
    log "Starting engine deployment..."
    readarray -t Engine_file_list < <(find "$build_drop_dir" -type f -exec basename {} \; | grep -E "$pattern_engine")
    get_former_version "$version" "engine"
    read major minor patch build <<< $(extract_version_components "$version")
    target_dir="${engine_dir}/${major}.${minor}.${patch}"
    mkdir -p "$target_dir"

    log "Copying files..."
    copy_files "$build_drop_dir" "$target_dir" "${Engine_file_list[@]}"
    copy_files "$engine_dir/$former_version" "$target_dir" "check_reserved.sql"

    latest_dir="${engine_dir}/${major}.${minor}_latest"
    mkdir -p "$latest_dir"
    log "Creating symbolic links in ${latest_dir} -latest files pointing to ${target_dir} files"
    make_symbolic_links "$target_dir" "$latest_dir" "$version" "${Engine_file_list[@]}"

    log "Creating symbolic link ${engine_dir}/${major}.${minor} pointing to ${target_dir}"
    ln -Tfs "$target_dir" "${engine_dir}/${major}.${minor}"

    log  "Updating MD5 checksums..."
    local md5_file="${target_dir}/md5sum-${version}.txt"
    touch "$md5_file"
    for file in "${Engine_file_list[@]}"; do
        grep "$file" "${build_drop_dir}/hash.md5" >> "$md5_file"
    done

    log "Engine deployment complete."
}

function deploy_jdbc() {
    log "Starting JDBC deployment..."
	readarray -t JDBC_file_list < <(find $build_drop_dir -type f -name "${pattern_jdbc}" -exec basename {} \;)
	jdbc_version=`echo ${JDBC_file_list[0]} | cut -d '-' -f 2`

    get_former_version "$jdbc_version" "jdbc"
    read major minor patch build <<< $(extract_version_components "$jdbc_version")

    log "Copying JDBC files..."
    copy_files "$build_drop_dir" "$jdbc_dir" "${JDBC_file_list[@]}"

    log "Creating symbolic links for JDBC..."
    make_symbolic_links "$jdbc_dir" "$jdbc_dir" "$jdbc_version" "${JDBC_file_list[@]}"


    local latest_jdbc_file=""
    for file in "${JDBC_file_list[@]}"; do
        if [[ "$file" =~ -cubrid\.jar$ ]]; then
            latest_jdbc_file="$file"
            break
        fi
    done

    if [[ -f "$jdbc_dir/filelist.txt" && -n "$latest_jdbc_file" ]]; then
        log "Updating JDBC file list with $latest_jdbc_file"
        sed -i "\|${former_version}|i ${latest_jdbc_file}" "$jdbc_dir/filelist.txt"
        log "Updated JDBC file list."
    else
        log "No JDBC file list to update or latest_jdbc_file is empty"
    fi

    log "JDBC deployment complete."
}

function deploy_cci() {
    log "Starting CCI deployment..."
    readarray -t CCI_file_list < <(find $build_drop_dir -type f -name "${pattern_cci}" ! -name "*debug*" -exec basename {} \;)
    cci_version=`echo ${CCI_file_list[0]} | cut -d '-' -f 3-4`
    get_former_version "$cci_version" "cci"
    read major minor patch build <<< $(extract_version_components "$cci_version")

    log "Copying CCI files..."
    local target_dir="${cci_dir}/${major}.${minor}.${patch}"
    mkdir -p "$target_dir"
    copy_files "$build_drop_dir" "$target_dir" "${CCI_file_list[@]}"

    if [ "$release_type" == "patch" ]; then
        echo "Removing latest symbolic links from former version..."
        find "${cci_dir}/${former_version}" -type l -name '*latest*' -exec rm {} \;
    fi

    log "Creating symbolic links for CCI..."
    latest_dir="${cci_dir}/${major}.${minor}_latest"
    mkdir -p "$latest_dir"
    make_symbolic_links "$target_dir" "$latest_dir" "$cci_version" "${CCI_file_list[@]}"
    ln -Tfs "$target_dir" "${cci_dir}/${major}.${minor}"

    log "CCI deployment complete."
}

function display_results() {
    echo "-----------------------------------------------------"
    echo "Deployment Results"
    echo "-----------------------------------------------------"
    echo "Engine Deployment:"
    ls -alt $engine_dir | head
    echo "-----------------------------------------------------"
    echo "JDBC Driver Deployment:"
    ls -alt $jdbc_dir | head
    head "$jdbc_dir/filelist.txt"
    echo "-----------------------------------------------------"
    echo "CCI Driver Deployment:"
    ls -alt $cci_dir | head
    echo "-----------------------------------------------------"
    echo "Deployment Complete!"
}

function deploy_default() {
	deploy_engine
	deploy_jdbc
	deploy_cci
	display_results
}

function main() {
    case "$task" in
        deploy)
            deploy_default
            ;;
        deploy_engine)
            deploy_engine
            ;;
        deploy_jdbc)
            deploy_jdbc
            ;;
        deploy_cci)
            deploy_cci
            ;;
        display_results)
            display_results
            ;;
        *)
            print_help
            exit 1
            ;;
    esac
}

# Ensure version and task are provided
if [ $# -lt 2 ]; then
    print_help
    exit 1
fi

log "Script started with version: $version and task: $task"
parse_version
main

