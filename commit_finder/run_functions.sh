#!/bin/bash

function IsGitExtensionBuild() {
    local buildFile=$1
    local buildNumber=$(echo $buildFile | grep -Pom 1 '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,7}')
    local startNumber="0100010000006858"
    local curNumber=$(echo $buildNumber | awk -F '.' '{printf("%03d%03d%03d%07d", $1, $2, $3, $4)}')

    if [ "$curNumber" -ge "$startNumber" ]; then
        return 0  # true
    else
        return 1  # false
    fi
}

function run_build() {
    ./build.sh -g ninja -z shell
}

function run_install() {
    local buildDir=~/cubrid/build_x86_64_release
    local buildFile=$(ls -t ${buildDir}/CUBRID*.sh | head -n 1)
    local cub="CUBRID"
    local curDir=$(pwd)

    if [ "$CUBRID" ]; then
        cd "$CUBRID" && cd .. || cd "$HOME"
    else
        cd "$HOME"
    fi

    echo ""
    echo "===== Installing CUBRID with $buildFile ====="
    echo ""

    if [ ! -f "$buildFile" ]; then
        echo "[ERROR]: The build file $buildFile does not exist."
        return 1
    fi

    chmod +x "$buildFile"
    cubrid service stop >/dev/null 2>&1
    [ -d "$cub" ] && rm -rf "$cub"

    if IsGitExtensionBuild "$buildFile"; then
        mkdir -p "$cub"
        cp "$buildFile" "$cub"
        cd "$cub"
        sh "$buildFile" >/dev/null <<EOF
y
n
EOF
    else
        sh "$buildFile" > /dev/null <<EOF
yes
EOF
    fi

    if [ $? -ne 0 ]; then
        echo "[ERROR]: Installation failed - $buildFile"
        cd "$curDir"
        return 1
    fi

    if [ -f ~/.cubrid.sh ]; then
        source ~/.cubrid.sh
        echo "CUBRID has been installed successfully."
        cpCCIDriver
    else
        echo "[ERROR]: Unable to source CUBRID environment settings."
        return 1
    fi

    cd "$curDir"
}

function cpCCIDriver()
{
    cci_header=(`find $CUBRID/cci -name "*.h"`)

    for header_list in ${cci_header[@]}; do
        filename=`basename "${header_list}"`
        rm -rf $CUBRID/include/${filename}
        cp -rf ${header_list} $CUBRID/include/
    done

    osname=`uname`
    case "$osname" in
        "Linux")
            OS="Linux";;
        *)
            OS="Windows_NT";;
    esac

    if [ "$OS" = "Linux" ]; then
        cci_lib=(`find $CUBRID/cci -name "libcascci*"`)

        for lib_list in ${cci_lib[@]}; do
            filename=`basename "${lib_list}"`
            rm -rf $CUBRID/lib/${filename}
            cp -rf ${lib_list} $CUBRID/lib/
        done
    else
        cp $CUBRID/cci/lib/cascci.lib $CUBRID/lib
        cp $CUBRID/cci/bin/cascci.dll $CUBRID/bin
    fi

}

function run_test() {
    local testcase=$1
    local TCROOTDIRNAME=~/cubrid-testcases-private-ex
    local currdir=$(pwd)

    if [ ! -e "$TCROOTDIRNAME" ]; then
        echo "Check testcases path: $TCROOTDIRNAME does not exist."
        return 1
    fi

    local testdir=$(dirname "$testcase")
    local testfile=$(basename "$testcase")
    cd "$TCROOTDIRNAME/$testdir"

    if [ ! -f "$testfile" ]; then
        echo "$testcase does not exist in $TCROOTDIRNAME."
        cd "$currdir"
        return 1
    fi

    sh "$testfile"
    local nameNotExt="${testfile%.*}"
    local NOKCnt=$(grep -rw NOK "${nameNotExt}.result" | wc -l)

    cd "$currdir"
    [ $NOKCnt -ge 1 ] && { echo "$testcase ==> NOK"; return 1; } || { echo "$testcase ==> OK"; return 0; }
}

