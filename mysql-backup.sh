#!/bin/bash
# Program
#  Mysql数据库备份脚本
#  使用Mysqlhotcopy备份myisam类型表
#  用Mydumper备份innodb类型表
# Author Ryanlau<showq#qq.com>
# History
#   2014/10/23-1.0
# Help
#  读取conf/xx.conf

#

# DEBUG=true

# trap 'echo "before execute line:$LINENO, OPTIONS=${OPTIONS[@]}"' DEBUG

#######################################
# Initialize variables
#######################################
OLD_DIR=${1:-`pwd`}
EXEC_DIR=${1:-`dirname $0`}
# your MySQL server's name
SERVER=`hostname -f`
# your mysqlhotcopy
MYHOTCOPY=$(which mysqlhotcopy)
# your mydumper
MYDUMPER=$(which mydumper)

#######################################
# Functions
#######################################
function die()
{
	echo >&2 "$@"
	exit 1
}
#
function mysqlCommand(){
  echo `mysql -h $1 --user=$2 --password=$3 -Bse "$4"`;
}
#
function startCommentLine(){
  echo -e "\033[$1#################### \033[0m"
  echo -e "\033[$1##$2 \033[0m"
}
#
function commentLine(){
  echo -e "\033[$1#------ $2 \033[0m"
}
#
function endCommentLine(){
  echo -e "\033[$1##$2 \033[0m"
  echo -e "\033[$1#################### \033[0m"
  echo " "
  echo " "
}
#
function alertMsg(){
  startCommentLine $1
  commentLine 31m $2
  endCommentLine
}
#
function noticeMsg(){
  startCommentLine $1
  commentLine 34m $2
  endCommentLine
}
#
function successMsg(){
  startCommentLine $1
  commentLine 32m $2
  endCommentLine
}

# Switch execute directory
cd $EXEC_DIR

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
  OPTIONS[5]=${DBMAIL:-${BACKUP_MAIL}}
  OPTIONS[6]=${DBEMAILS:-${BACKUP_EMAILS}}

	if [ -z "${OPTIONS[4]}" ]; then
    DBS=`mysqlCommand ${OPTIONS[0]} ${OPTIONS[1]} ${OPTIONS[2]} "Show databases;"`
    TITLE="Creating list of all your databases... \n\n"
    BODY="Please modify config file, Usage "
    BODY=$BODY$DBS
    alertMsg $TITLE $BODY
	fi

  # Fetch all tables
  DBC=`mysqlCommand ${OPTIONS[0]} ${OPTIONS[1]} ${OPTIONS[2]} "use ${OPTIONS[4]}; show tables;"`

  if [ -z "${DBC}" ]; then
    alertMsg "Please check dbname" "${OPTIONS[4]} is non-exist"
  fi

  CHECKTYPE=true
  for tbl in ${DBC}
  do
    myc="use ${OPTIONS[4]}; SHOW TABLE STATUS FROM ${OPTIONS[4]} WHERE name='$tbl';"
    DBD=`mysqlCommand ${OPTIONS[0]} ${OPTIONS[1]} ${OPTIONS[2]} "$myc"`
    if [[ -z "$DBD" ]]; then
      CHECKTYPE=false
      break;
    fi
  done

  if [[ !$CHECKTYPE ]]; then
    alertMsg "Type is error" "Body"
  fi


  # @TODO 忽略表
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

  # 针对DRUPAL优化。不存储缓存表数据

  startCommentLine "Backing up MySQL database ${OPTIONS[4]} on ${OPTIONS[0]}..."
  DB_BACKDIR=${BACKDIR}/${OPTIONS[4]}
  DB_DATE_BACKDIR=${DB_BACKDIR}/${DATE}
  if [ ! -d $DB_DATE_BACKDIR ]; then
    commentLine 32m "Creating $DB_DATE_BACKDIR for ${OPTIONS[4]}..."
    mkdir -p $DB_DATE_BACKDIR
  fi

  test ${OPTIONS[0]} == "localhost" && SERVER=`hostname -f` || SERVER=${OPTIONS[0]}
  if [ ${OPTIONS[3]} == 'myisam' ]; then
    # mysqlhotcopy
    sudo $MYHOTCOPY -u ${OPTIONS[1]} -p ${OPTIONS[2]} --addtodest ${OPTIONS[4]} $DB_DATE_BACKDIR
  else
    # mydumper
    # -L $DB_DATE_BACKDIR/mysql-backup.log
    $MYDUMPER -o $DB_DATE_BACKDIR -r 10000 -c -e -u ${OPTIONS[1]} -p ${OPTIONS[2]} -B ${OPTIONS[4]}
    # 压缩比-6
  fi
  # mysqldump
  # mysqldump -h ${DBHOST[$KEY]} --user=${DBUSER[$KEY]} --password=${DBPASS[$KEY]} ${DBOPTIONS[$KEY]} $database $TABLES > \
  # $BACKDIR/$SERVER-$database-$DATE-mysqlbackup.sql

  # Check backup
  BAK_FILENAME=${OPTIONS[4]}-${DATE//\:/-}.tar.gz
  BAK_FILE=$DB_BACKDIR/${BAK_FILENAME}

  # 是否存在有效备份
  if [ -r $DB_DATE_BACKDIR ] && [ ! -z "$(ls $DB_DATE_BACKDIR)" ]; then
    cd $DB_BACKDIR
    tar -czPf $BAK_FILE $DATE
    cd -
    sudo rm -rf $DB_DATE_BACKDIR

    # if you have the mail program 'mutt' installed on
    # your server, this script will have mutt attach the backup
    # and send it to the email addresses in $EMAILS
    if  [ ${OPTIONS[5]} = "y" ]; then
      BODY="Your backup is ready! \n\n"
      BODY=$BODY`cd $DB_BACKDIR; md5sum ${BAK_FILE};`
      ATTACH=` echo -n "-a ${BAK_FILE} "; `

      # echo -e "$BODY" | mutt -s "$SUBJECT" $ATTACH -- ${OPTIONS[6]}
      #if [[ $? -ne 0 ]]; then
      #  echo -e "ERROR:  Your backup could not be emailed to you! \n";
      #else
      #  echo -e "Your backup has been emailed to you! \n"
      #fi
    fi
  fi




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

  endCommentLine "The database ${OPTIONS[4]} is backed up!"
	unset OPTIONS
done
cd $OLD_DIR
