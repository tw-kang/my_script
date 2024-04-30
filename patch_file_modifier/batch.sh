# !/bin/bash

set -x
#usage : sh batch.sh jdbc_sql_8.4.1_D_fail
cur_dir=`pwd`
case_dir=$cur_dir/work
origin_dir=${HOME}/cubrid-testcases
#origin_dir=${HOME}/cubrid-testcases-private
list=$1

#clean
rm -f $cur_dir/before.out
rm -f $cur_dir/after.out
rm -rf $case_dir
rm -f sql_batch.conf
cd $origin_dir
git clean -fd
git checkout *
cd -

#make directory and copy
mkdir -p $case_dir
xargs -a $list dirname | xargs -t -I % sh -c "{ mkdir -p $case_dir/%;}"
xargs -a $list dirname | sed "s#cases#answers#g" | xargs -t -I % sh -c "{ mkdir -p $case_dir/%;}"

#xargs -t -a $list -I % sh -c "{ cp $origin_dir/medium/% $case_dir/%;}"
xargs -t -a $list -I % sh -c "{ cp $origin_dir/sql/% $case_dir/%;}"
#sed -e "s#cases#answers#g" -e"s#\.sql#\.answer#g" $list| xargs -t -I % sh -c "{ cp $origin_dir/medium/% $case_dir/%;}"
sed -e "s#cases#answers#g" -e"s#\.sql#\.answer#g" $list| xargs -t -I % sh -c "{ cp $origin_dir/sql/% $case_dir/%;}"

#for the result of testcase run ctp with copied cases
ver=`echo $list | cut -d'_' -f 3`
cp ${HOME}/jdbc_driver_compat/jdbc-$ver-cubrid.jar ${CUBRID}/jdbc/
ln -Tfs jdbc-$ver-cubrid.jar $CUBRID/jdbc/cubrid_jdbc.jar
#cp ${CTP_HOME}/conf/medium_no_reuseoid.conf $cur_dir/sql_batch.conf
#cp ${CTP_HOME}/conf/sql_dont_reuse_heap.conf $cur_dir/sql_batch.conf
cp ${CTP_HOME}/conf/sql.conf $cur_dir/sql_batch.conf
sed -i -e "s#scenario.*=.*#scenario=$case_dir#g" $cur_dir/sql_batch.conf

ctp.sh sql -c $cur_dir/sql_batch.conf > $cur_dir/before.out
cat $cur_dir/before.out

sh fin_make_patch.sh $1 $case_dir
#exit
cd $origin_dir
git status

#check patch file is correct
#cd $origin_dir/medium
cd $origin_dir/sql
patch_file=`echo $list | sed "s#fail#patch#g"`
patch -p0 -f < config/daily_regression_test_exclude_list_compatibility/patch_files/$patch_file
#sed -e "s#cases#answers#g" -e "s#\.sql#\.answer#g" $cur_dir/$list| xargs -t -I % sh -c "{ cp -v $origin_dir/medium/% $case_dir/%;}"
sed -e "s#cases#answers#g" -e "s#\.sql#\.answer#g" $cur_dir/$list| xargs -t -I % sh -c "{ cp -v $origin_dir/sql/% $case_dir/%;}"
ctp.sh sql -c $cur_dir/sql_batch.conf > $cur_dir/after.out
cat $cur_dir/after.out

have_fail=`grep -r "Fail:" $cur_dir/after.out | cut -d":" -f 2`
if [ ${have_fail} -eq 0 ] ; then
	git status | grep $ver | awk '{print $3}' | xargs -I% git add %
	git clean -fd
	git checkout *
	git commit -m "modified $list"
else
	echo "not done yet"
fi

cd -
