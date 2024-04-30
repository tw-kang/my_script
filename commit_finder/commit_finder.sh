#!/bin/bash

set -x

START_COMMIT=$1
END_COMMIT=$2
TEST_CASE_NAME=$3


#export MAKEFLAGS="-j"
#scl enable devtoolset-8 bash

cd ~/cubrid
git remote update origin
git checkout develop
if [ $? -ne 0 ]; then
    echo "Failed to checkout 'develop' branch."
    exit 1
fi
git pull origin develop
if [ $? -ne 0 ]; then
    echo "Failed to pull latest changes from 'develop' branch."
    exit 1
fi

git bisect start
git bisect bad $START_COMMIT
git bisect good $END_COMMIT

# git bisect에 사용할 테스트 스크립트를 정의합니다.
git bisect run bash -c "
source ~/twkang/run_functions.sh &&
run_build &&
run_install &&
run_test '$TEST_CASE_NAME'
"

# bisect가 완료되면 현재 커밋에 대한 설명을 출력하고, bisect 세션을 종료합니다.
git log -1
git bisect reset
