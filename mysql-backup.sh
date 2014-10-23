#!/bin/bash
# Program
#   Mysql数据库备份脚本, 使用Mysqlhotcopy备份myisam类型表
#   用Mydumper备份innodb类型表
# Author showq@qq.com
# History
#   2014/10/23-1.0
# Help
function die()
{
	echo >&2 "$@"
	exit 1
}
function mysqlCommand(){
  echo `mysql -h ${OPTIONS[0]} --user=${OPTIONS[1]} --password=${OPTIONS[2]} -Bse "$1"`;
}

function rule(){
  echo -e "\033[$1 $3------ $2 ------ \033[0m"
}

CONFIG=${1:-`dirname $0`/mysql-backup.conf}
[ -f "$CONFIG" ] && . "$CONFIG" || die "Could not load configuration file ${CONFIG}!"

# check of the backup directory exists
# if not, create it
if [ ! -d $BACKDIR ]; then
	echo -n "Creating $BACKDIR..."
	mkdir -p $BACKDIR
	echo "done!"
fi

for f in ./conf/*.conf
do
	#Read db.config
	INFO=`cat $f | grep -v ^$ | sed -n "s/\s\+//;/^#/d;p" ` && eval "$INFO"

	#Invoke default settings
	declare -a OPTIONS
	OPTIONS[0]=${DBHOST:-${BACKUP_HOST}}
	OPTIONS[1]=${DBUSER:-${BACKUP_USER}}
	OPTIONS[2]=${DBPASS:-${BACKUP_PASS}}
	OPTIONS[3]=${DBTYPE}
	OPTIONS[4]=${DBNAME}
  #@TODO: Add debug options echo ${OPTIONS[@]}

	if [ -z "${OPTIONS[4]}" ]; then
    rule 31m "Creating list of all your databases..." "|"
    DBS=`mysqlCommand "Show databases;"`
		echo "Please modify config file, Usage "
    echo "${DBS}!"
    exit 0
	fi

	#Check required parameter
	# @TODO
	# 1.数据库存在，有权限备份。
	# 2.数据库中表类型与配置相符。

  #@TODO 忽略表
	# filter out the tables to backup
	# if [ -n "${DBTABLES}" ]; then
	#   if  [ ${DBTABLESMATCH} = "exclude" ]; then
	#     TABLES=''
	#     for table in ${DBTABLES}; do
	#       TABLES="$TABLES --ignore-table=$table "
	#     done
	#   else
	#     TABLES=${DBTABLES}
	#   fi
	# fi

  # echo -n "Backing up database ${OPTIONS[4]}..."
  rule "32m" "Backing up MySQL database ${OPTIONS[4]} on ${OPTIONS[0]}..." "|"

  DB_BACKDIR=${BACKDIR}/${OPTIONS[4]}/${DATE}
  if [ ! -d $DB_BACKDIR ]; then
    rule "36m" "Creating $DB_BACKDIR for ${OPTIONS[4]}..." "|"
    mkdir -p $DB_BACKDIR
  fi
  test ${OPTIONS[0]} == "localhost" && SERVER=`hostname -f` || SERVER=${OPTIONS[0]}
  if [ ${OPTIONS[3]} == 'myisam' ]; then
    # mysqlhotcopy
    $MYHOTCOPY -u ${OPTIONS[1]} -p ${OPTIONS[2]} --addtodest ${OPTIONS[4]} $DB_BACKDIR
  else
    # mydumper
    $MYDUMPER -o $DB_BACKDIR -r 10000 -c -e -L $DB_BACKDIR/mysql-backup.log -u ${OPTIONS[1]} -p ${OPTIONS[2]} -B ${OPTIONS[4]}
    # 压缩比-6
    # gzip -f $BACKDIR/${OPTIONS[4]}/$DATE
  fi

  # mysqldump -h ${DBHOST[$KEY]} --user=${DBUSER[$KEY]} --password=${DBPASS[$KEY]} ${DBOPTIONS[$KEY]} $database $TABLES > \
  # $BACKDIR/$SERVER-$database-$DATE-mysqlbackup.sql
  # gzip -f -9 $BACKDIR/$SERVER-$database-$DATE-mysqlbackup.sql

	# if you have the mail program 'mutt' installed on
	# your server, this script will have mutt attach the backup
	# and send it to the email addresses in $EMAILS

  #@TODO: 增加压缩发送邮箱功能
	# if  [ $MAIL = "y" ]; then
	#   BODY="Your backup is ready! \n\n"
	#   BODY=$BODY`cd $BACKDIR; for file in *$DATE-mysqlbackup.sql.gz; do md5sum ${file};  done`
	#   ATTACH=`for file in $BACKDIR/*$DATE-mysqlbackup.sql.gz; do echo -n "-a ${file} ";  done`

	#   echo -e "$BODY" | mutt -s "$SUBJECT" $ATTACH -- $EMAILS
	#   if [[ $? -ne 0 ]]; then
	#     echo -e "ERROR:  Your backup could not be emailed to you! \n";
	#   else
	#     echo -e "Your backup has been emailed to you! \n"
	#   fi
	# fi

	# if  [ $DELETE = "y" ]; then
	#   OLDDBS=`cd $BACKDIR; find . -name "*-mysqlbackup.sql.gz" -mtime +$DAYS`
	#   REMOVE=`for file in $OLDDBS; do echo -n -e "delete ${file}\n"; done` # will be used in FTP

	#   cd $BACKDIR; for file in $OLDDBS; do rm -v ${file}; done
	#   if  [ $DAYS = "1" ]; then
	#     echo "Yesterday's backup has been deleted."
	#   else
	#     echo "The backups from $DAYS days ago and earlier have been deleted."
	#   fi
	# fi

  rule 36m "The database ${OPTIONS[4]} is backed up!" "|"
  echo ' '
  echo ' '
	unset OPTIONS
done


