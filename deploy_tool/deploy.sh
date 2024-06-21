#!/bin/bash
set -euo pipefail
version=$1
task=$2
jdbc_version=""
cci_version=""
former_version=""
major=""
minor=""
patch=""
build=""
release_type=""

# Define common regex patterns
pattern="(8|9|10|11|12).[0-9].[0-9]{1,2}.[0-9]{4}-[a-z0-9]{7}"
pattern_engine="CUBRID-${pattern}-Linux.x86_64.(rpm|sh|tar.gz)|CUBRID-Windows-x64-${pattern}.(zip|msi)|cubrid-${pattern}.(zip|tar.gz)"
pattern_jdbc="JDBC-*"
pattern_cci="CUBRID-CCI-*" 

# Use variables for common directory paths
build_drop_dir="/home/dist/data/CUBRID_Engine/nightly/daily_build/${version}/drop"
engine_dir=/home/dist/data/CUBRID_Engine
driver_dir=/home/dist/data/CUBRID_Drivers
target_dir=
jdbc_dir=${driver_dir}/JDBC_Driver
cci_dir=${driver_dir}/CCI_Driver
#############################################

function print_help() {
	echo
    echo "Usage: bash $0 version {deploy_engine|deploy_jdbc|deploy_cci|display_results}"
    echo "Example: bash $0 11.4.0.1142-earfsd deploy_engine"
    echo "If no task is provided, the script will run the default sequence: init, deploy_engine, deploy_cci, deploy_jdbc, display_results"
	echo
}

# Validate version pattern at the beginning
if ! [[ $version =~ $pattern ]]; then
    echo "Error: Version format is invalid. Expected format: major.minor.patch.build-hash"
    print_help
    exit 1
fi


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
    done
}

# Function to make symbolic links for given files with a version substitution
function make_symbolic_links() {
    local target_dir=$1
    local version=$2
    local new_version=$3
    local files=("${@:4}")
    cd "${target_dir}"
    for file in "${files[@]}"; do
        local link_name=$(echo "$file" | sed "s/${version}/${new_version}-latest/g")
        ln -Tfs "$file" "$link_name"
    done
}

# Function to handle version comparison and extraction
function extract_version_components() {
    local version=$1
    echo "$version" | awk -F'[-.]' '{print $1,$2,$3,$4}' # Outputs major minor patch build
}

function init() {
    readarray -t Engine_file_list < <(find "$build_drop_dir" -type f -exec basename {} \; | grep -E "$pattern_engine")
    readarray -t JDBC_file_list < <(find $build_drop_dir -type f -name "${pattern_jdbc}" -exec basename {} \;)
    readarray -t CCI_file_list < <(find $build_drop_dir -type f -name "${pattern_cci}" ! -name "*debug*" -exec basename {} \;)

	jdbc_version=`echo ${JDBC_file_list[0]} | cut -d '-' -f 2`
	cci_version=`echo ${CCI_file_list[0]} | cut -d '-' -f 3-4`
	echo engine_version: $version
	echo jdbc_version: $jdbc_version
	echo cci_version: $cci_version
	echo deploy_dir: $target_dir
	echo build_dir: $build_drop_dir
	echo engine_dir: $engine_dir
	echo engine_list: ${Engine_file_list[@]}
	echo JDBC_file_list: ${JDBC_file_list[@]}
	echo CCI_file_list: ${CCI_file_list[@]}
}

function get_former_version() {
    local in_version=$1
    local in_type=$2
    local dir_path=$(eval echo \${${in_type}_dir})
    local patt=""

    # Use extract_version_components to simplify version parsing
    read major minor patch build <<< $(extract_version_components "$in_version")
    if [ "$in_type" == "jdbc" ]; then
        patt="[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"
        local versions_list=$(find "$dir_path" -type f | grep -Eo "$patt" | sort -Vu)
    else
        patt="[0-9]+\.[0-9]+\.[0-9]+"
        local versions_list=$(find "$dir_path" -type d | grep -Eo "$patt" | sort -Vu)
    fi

    # Find all relevant versions
    # Extract the version immediately preceding the input version in sorted list
    local previous_version=$(echo "$versions_list" | grep -B1 "$major.$minor.$patch" | head -n1)

    # Determine release type based on version difference
    read prev_major prev_minor prev_patch prev_build <<< $(extract_version_components "$previous_version")
    
    if [ "$major" -ne "$prev_major" ]; then
        release_type="major"
    elif [ "$minor" -ne "$prev_minor" ]; then
        release_type="minor"
    elif [ "$patch" -ne "$prev_patch" ]; then
        release_type="patch"
    else
        release_type="build"
    fi

    echo "Previous version: $previous_version"
    echo "Release type: $release_type"
    former_version="$previous_version"
}

function deploy_engine() {
    init
    echo "Starting engine deployment..."
    get_former_version "$version" "engine"
    read major minor patch build <<< $(extract_version_components "$version")

    target_dir="${engine_dir}/${major}.${minor}.${patch}"

    # Ensure the target directory exists
    mkdir -p "$target_dir"

    echo "Copying files..."
    # Utilize copy_files to copy Engine files to the target directory
    copy_files "$build_drop_dir" "$target_dir" "${Engine_file_list[@]}"
    copy_files "$engine_dir/$former_version" "$target_dir" "check_reserved.sql"

    # # If this is a patch release, remove 'latest' symbolic links from the former version directory
    # if [ "$release_type" == "patch" ]; then
    #     echo "Removing latest symbolic links from former version..."
    #     find "${engine_dir}/${former_version}" -type l -name '*latest*' -exec rm {} \;
    # fi

    echo "Creating symbolic links..."
    # Create a [major].[minor]_latest directory
    latest_dir="${engine_dir}/${major}.${minor}_latest"
    mkdir -p "$latest_dir"

    # Create symbolic links for the new version in the _latest directory
    make_symbolic_links "$latest_dir" "$version" "$major.$minor" "${Engine_file_list[@]}"

    # Update the symbolic links at the engine directory level
    ln -Tfs "$target_dir" "${engine_dir}/${major}.${minor}"

    echo "Updating MD5 checksums..."
    # Handle MD5 checksum file creation
    local md5_file="${target_dir}/md5sum-${version}.txt"
    touch "$md5_file"
    for file in "${Engine_file_list[@]}"; do
        grep "$file" "${build_drop_dir}/hash.md5" >> "$md5_file"
    done

    echo "Engine deployment complete."
}

function deploy_jdbc() {
    init
    echo "Starting JDBC deployment..."
    # Extract version components for JDBC version
    get_former_version "$jdbc_version" "jdbc"
    read major minor patch build <<< $(extract_version_components "$jdbc_version")

    echo "Copying JDBC files..."
    # Copy JDBC files using the generalized function
    copy_files "$build_drop_dir" "$jdbc_dir" "${JDBC_file_list[@]}"

    echo "Creating symbolic links for JDBC..."
    # Create symbolic links for the JDBC files
    make_symbolic_links "$jdbc_dir" "$jdbc_version" "$major.$minor" "${JDBC_file_list[@]}"

    # Optionally, you might want to update a file list or manifest if your deployment requires it
    local latest_jdbc_file=""
    for file in "${JDBC_file_list[@]}"; do
        if [[ "$file" =~ -cubrid\.jar$ ]]; then
            latest_jdbc_file="$file"
            break
        fi
    done

    if [[ -f "$jdbc_dir/filelist.txt" ]]; then
        sed -i "/${former_version}/ i ${latest_jdbc_file}" "$jdbc_dir/filelist.txt"
        echo "Updated JDBC file list."
    fi

    echo "JDBC deployment complete."
}

function deploy_cci() {
    init
    echo "Starting CCI deployment..."
    # Extract version components for CCI version
    get_former_version "$cci_version" "cci"
    read major minor patch build <<< $(extract_version_components "$cci_version")

    # Determine the target directory for deployment
    local target_dir="${cci_dir}/${major}.${minor}.${patch}"
    mkdir -p "$target_dir"

    echo "Copying CCI files..."
    # Copy CCI files using the generalized function
    copy_files "$build_drop_dir" "$target_dir" "${CCI_file_list[@]}"

    # Remove 'latest' symbolic links from the former version directory if this is a patch release
    if [ "$release_type" == "patch" ]; then
        echo "Removing latest symbolic links from former version..."
        find "${cci_dir}/${former_version}" -type l -name '*latest*' -exec rm {} \;
    fi

    echo "Creating symbolic links for CCI..."
    # Create a [major].[minor]_latest directory
    latest_dir="${cci_dir}/${major}.${minor}_latest"
    mkdir -p "$latest_dir"

    # Create symbolic links for the CCI files in the _latest directory
    make_symbolic_links "$latest_dir" "$cci_version" "$major.$minor" "${CCI_file_list[@]}"

    # Update directory-level symbolic links to point to the new version
    ln -Tfs "$target_dir" "${cci_dir}/${major}.${minor}"

    echo "CCI deployment complete."
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

function deploy_default ()
{
  init
  deploy_engine
  deploy_cci
  deploy_jdbc
  display_results
}

# Initial version check and setup
if ! [[ $version =~ $pattern ]]; then
    echo "Error: Invalid version format."
    print_help
    exit 1
fi

# Main Execution Logic
case $task in
    "")
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
        echo "Error: Invalid task."
		print_help
        exit 1
        ;;
esac

