#!/bin/bash
# Program
#  Mysql数据库备份脚本
#  使用Mysqlhotcopy备份myisam类型表
#  用Mydumper备份innodb类型表
# Author Ryanlau<showq#qq.com>
# History
#   2014/10/23-1.0
# Help
#  此脚本会读取$HOME/mysql-backup下的xx.conf
#

# DEBUG=true

# trap 'echo "before execute line:$LINENO, OPTIONS=${OPTIONS[@]}"' DEBUG

#######################################
# Initialize variables
#######################################
#shell文件存放目录
INIT_DIR=${1:-`pwd`}
#执行目录
EXEC_DIR=${1:-`dirname $0`}
# your MySQL server's name
SERVER=`hostname -f`
# your mysqlhotcopy
MYHOTCOPY=$(which mysqlhotcopy)
# your mydumper
MYDUMPER=$(which mydumper)
# your mysqldump
MYSQLDUMP=$(which mysqldump)

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
	#Read .conf file
	INFO=`cat $f | grep -v ^$ | sed -n "s/\s\+//;/^#/d;p" ` && eval "$INFO"

	#Invoke default settings
	DBHOST=${DBHOST:-${BACKUP_HOST}}
	DBUSER=${DBUSER:-${BACKUP_USER}}
	DBPASS=${DBPASS:-${BACKUP_PASS}}
	DBENGINE=${DBENGINE:-"myisam"}
	DBNAME=${DBNAME}
  DBMAIL=${DBMAIL:-${BACKUP_MAIL}}
  DBMAILTO=${DBMAILTO:-${BACKUP_MAILTO}}
  DBOPTIONS=${DBOPTIONS:-""}

  DBSQLDUMP_TABLES=${DBSQLDUMP_TABLES:-""}

	if [ -z "$DBNAME" ]; then
    DBS=`mysqlCommand $DBHOST $DBUSER $DBPASS "Show databases;"`
    TITLE="Creating list of all your databases... \n\n"
    BODY="Please modify config file, Usage "
    BODY=$BODY$DBS
    alertMsg $TITLE $BODY
	fi

  # Fetch all tables from databases
  DB_TABLE_NAMES=`mysqlCommand $DBHOST $DBUSER $DBPASS "use $DBNAME; show tables;"`
  
  # If DB_TABLE_NAMES is empty, DBNAME no exists
  if [ -z "$DB_TABLE_NAMES" ]; then
    alertMsg "Please check dbname" "$DBNAME is non-exist"
  fi

  # 检查库中，所有的表引擎与设置一致
  CHECKTYPE=true
  DBENGINE_UPPERCASE=$(echo $DBENGINE | tr '[a-z]' '[A-Z]');

  for tbl in $DB_TABLE_NAMES
  do
    #myc="use ${DBNAME}; SHOW TABLE STATUS FROM ${DBNAME} WHERE name='$tbl';"
    myCommand="use information_schema;"
    myCommand=$myCommand"select engine from information_schema.tables where table_schema='$DBNAME' AND table_name='$tbl';"
    tblENGINE=`mysqlCommand $DBHOST $DBUSER $DBPASS "$myCommand"`

    tblENGINE_UPPERCASE=$(echo $tblENGINE | tr '[a-z]' '[A-Z]');

    if [[ "$tblENGINE_UPPERCASE" != "$DBENGINE_UPPERCASE" ]]; then
      CHECKTYPE=false
      break;
    fi
  done

  if [[ ! $CHECKTYPE ]]; then
    alertMsg "Type is error" "Body"
  fi

  startCommentLine 32m "Backing up MySQL database $DBNAME on $DBHOST..."
  DB_BACKDIR=$BACKDIR/$DBNAME
  DB_DATE_BACKDIR=$DB_BACKDIR/$DATE
  if [ ! -d $DB_DATE_BACKDIR ]; then
    commentLine 32m "Creating $DB_DATE_BACKDIR for $DBNAME..."
    mkdir -p $DB_DATE_BACKDIR
  fi

  test $DBHOST == "localhost" && SERVER=`hostname -f` || SERVER=$DBHOST

  case $DBENGINE in
    "myisam")
      # mysqlhotcopy
      C="sudo $MYHOTCOPY -u $DBUSER -p $DBPASS --addtodest $DBNAME$DBOPTIONS $DB_DATE_BACKDIR";;
    "mydumper")
      # mydumper
      C="$MYDUMPER -o $DB_DATE_BACKDIR -r 10000 -c -e -u $DBUSER -p $DBPASS -B $DBNAME $DBOPTIONS";;
    "mysqldump")
      # mysqldump
      C="$MYSQLDUMP -h $DBHOST --user=$DBUSER --password=$DBPASS --add-drop-table $DBOPTIONS $DBNAME $DBSQLDUMP_TABLES -r$DB_DATE_BACKDIR/backup.sql";;
  esac
  commentLine 33m "Command: $C"
  $C

  # Check backup
  BAK_FILENAME=$DBNAME-${DATE//\:/-}.tar.gz
  BAK_FILE=$DB_BACKDIR/$BAK_FILENAME

  # 是否存在有效备份
  if [ -r $DB_DATE_BACKDIR ] && [ ! -z "$(ls $DB_DATE_BACKDIR)" ]; then
    cd $DB_BACKDIR
    tar -czPf $BAK_FILE $DATE
    cd -
    sudo rm -rf $DB_DATE_BACKDIR

    # if you have the mail program 'mutt' installed on
    # your server, this script will have mutt attach the backup
    # and send it to the email addresses in $EMAILS
    if  [ $DBMAIL = "y" ]; then
      BODY="Your backup is ready! \n\n"
      BODY=$BODY`cd $DB_BACKDIR; md5sum $BAK_FILE;`
      ATTACH=` echo -n "-a $BAK_FILE "; `

      # echo -e "$BODY" | mutt -s "$SUBJECT" $ATTACH -- $DBMAILTO
      #if [[ $? -ne 0 ]]; then
      #  echo -e "ERROR:  Your backup could not be emailed to you! \n";
      #else
      #  echo -e "Your backup has been emailed to you! \n"
      #fi
    fi
  fi

  # @TODO 默认保存1个月中，30个数据备份。
	# if  [ $DBDELETE = "y" ]; then
	#  OLDDBS=`cd $BACKDIR; find . -name "*-mysqlbackup.sql.gz" -mtime +$DAYS`
	#  REMOVE=`for file in $OLDDBS; do echo -n -e "delete ${file}\n"; done` 

	#  cd $BACKDIR; for file in $OLDDBS; do rm -v ${file}; done
	#  if  [ $DAYS = "1" ]; then
	#    echo "Yesterday's backup has been deleted."
	#  else
	#    echo "The backups from $DAYS days ago and earlier have been deleted."
	#  fi
	# fi

  endCommentLine 32m "The database $DBNAME is backed up!"
	unset DBHOST DBUSER DBPASS
  unset DBENGINE DBNAME DBMAIL
  unset DBMAILTO DB_TABLE_NAMES
done
cd $INIT_DIR
#切换回目录。
