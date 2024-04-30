# !/bin/bash

#set -x

fail_list=$1
cur_dir=`pwd`
compat_category=
compat_ver=
compat_type=
major=
minor=
patch=
patch_file=
tc_path=$2

function help() {
        echo
        echo "usage: ./$(basename $0) jdbc_sql_8.4.1_D_fail ~/cubrid-testcases"
        echo
}

function init () {
	compat_category=`echo $fail_list | cut -d"_" -f 2`
	#for sql_ext
#	compat_ver=`echo $fail_list | cut -d "_" -f 4`
#	compat_type=`echo $fail_list | cut -d "_" -f 5`
	compat_ver=`echo $fail_list | cut -d "_" -f 3`
	compat_type=`echo $fail_list | cut -d "_" -f 4`
	major=`echo $compat_ver | cut -d"." -f 1`
	minor=`echo $compat_ver | cut -d"." -f 2`
	patch=`echo $compat_ver | cut -d"." -f 3`

	if [ -z $patch ] ; then
		patch=0
		compat_ver=$major.$minor.$patch
	fi

	patch_file=${HOME}/cubrid-testcases/$compat_category/config/daily_regression_test_exclude_list_compatibility/patch_files/jdbc_${compat_category}_${compat_ver}_${compat_type}_patch
#	patch_file=${HOME}/cubrid-testcases/$compat_category/config/daily_regression_test_exclude_list_compatibility/patch_files/jdbc_${compat_category}_ext_${compat_ver}_${compat_type}_patch

	echo tc_path : $tc_path
	echo target patch file : $patch_file

}

function parse_file (){
	sql_list=()
	sql_list+=(`cat $cur_dir/$fail_list`)
	cd $cur_dir
}

function write_file (){
	cd $tc_path
	i=0
	j=0
	for file in "${sql_list[@]}" ; do
		
		comp_a=`echo $file | sed -e "s#/cases/#/answers/#g" -e "s#\.sql#.answer#g"`
		comp_r=`echo $file | sed -e "s#\.sql#.result#g"`

		rm -r temp.out
		echo "Index: $comp_a" > temp.out 
		echo "===================================================================" >> temp.out
		#use a option when the result have binary file compare
		#diff -urN ${comp_a} ${comp_r} >> temp.out
		diff -aurN ${comp_a} ${comp_r} >> temp.out
		sed -i "s#$comp_r#$comp_a#g" temp.out
	
		is_exists_1=`grep -r "Index: $comp_a" ${patch_file} |wc -l`
		if [ $is_exists_1 -eq 1 ] ; then
			echo have former patch on $comp_a
			idx=()
			idx+=(`grep -n -r "Index: " ${patch_file} | grep -A1 "$comp_a" | cut -d":" -f1`)
			start=${idx[0]}
			if [ `echo ${#idx[@]}` -eq 1 ] ; then
				idx+=(`nl ${patch_file}| tail -n 1 | cut -f1`)
				end=${idx[1]}
			else
				end=${idx[1]}
				end=$((end-1))
			fi
			sed -i "${end} r temp.out" ${patch_file}
			sed -i "${start},${end}d" ${patch_file}
			echo $start to $end is replaced.
			j=$((j+1))
		else
			cat temp.out >> $patch_file
			echo contents is added on the end of file.
		fi
		
		
		i=$((i+1))
	done
	echo =====================
	echo loop is done $i
	echo former file num : $j
	
	cd $cur_dir	
}

# main
pattern="jdbc_(sql|sql_ext|medium)_(8|9|10|11).[0-9].[0-9]_(D|S64)_fail"
if [[ $1 =~ $pattern ]] && [ -n $2 ] ; then
        continue
else
        help
        exit 0
fi

init
parse_file
write_file

exit
