#!/bin/bash
# Program
#  Mysql数据库备份脚本
#  使用Mysqlhotcopy备份myisam类型表
#  用Mydumper备份innodb类型表
# Author Ryanlau<showq#qq.com>
# History
#   2014/10/23-1.0
#   2014/11/10-2.0
# Help
#  此脚本会读取$HOME/mysql-backup下的xx.conf
#

#######################################
# for debug 
# trap 'echo "before execute line:$LINENO, OPTIONS=${OPTIONS[@]}"' DEBUG
#######################################

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

# $1 $fileBaseDir
# $2 $dbBackDir
# $3 $logBaseDir
function necessaryDirectory(){
  # check of the backup directory exists
  # if not, create it
  if [ ! -d $1 ]; then
    echo -n "Creating $1..."
    mkdir -p $1
    echo "done!"
  fi

  #dbBaseDir
  if [ ! -d $2 ]; then
    echo -n "Creating $2..."
    mkdir -p $2
    echo "done!"
  fi

  #logBaseDir
  if [ ! -d $3 ]; then
    echo -n "Creating $3..."
    mkdir -p $3
    echo "done!"
  fi

  if [ ! -d $1 ] || [ ! -d $2 ] || [ ! -d $3 ]; then
    TITLE="Miss required directory"
    BODY="Miss required directory, Please manually create"
    alertMsg $TITLE $BODY
  fi
}


#######################################
# install shell
if [ $0 = 'install' ]; then
  # @TODO Move global configuration file to /etc/
  echo 'Installed '
fi

#######################################
# Initialize variables
#######################################
#shell文件存放目录
initDir=${1:-`pwd`}
#执行目录
execDir=${1:-`dirname $0`}

# your mysql server's name
server=`hostname -f`
# your mysqlhotcopy
myHotcopy=$(which mysqlhotcopy)
# your mydumper
myDumper=$(which mydumper)
# your mysqldump
mysqlDump=$(which mysqldump)

# user config file directory for each sites
configDir=$HOME/.cron_unidump.d
#configDir
if [ ! -d $configDir ]; then
  echo -n "Creating $configDir..."
  mkdir -p $configDir
  echo "done!"
fi

########################################
# Basic backup file store directory
########################################
# file
G_fileBaseDir=/var/backup/files
# database
G_dbBaseDir=/var/backup/mysql
# log
G_logBaseDir=/var/log/backup

# date format that is appended to filename
dateStr=$(date -u +'%F-%T')
dateStrSuffix=${dateStr//\:/-}

fileOwn='vagrant:vagrant'

#######################################
# Shell program
#######################################
# @TODO Add global configuration

# Read basic configuration
CONFIG=${1:-`dirname $0`/cron_unidump.conf}
[ -f "$CONFIG" ] && . "$CONFIG" || die "Could not load configuration file ${CONFIG}!"


for f in $configDir/*.conf ; do
	#Read .conf file
	INFO=`cat $f | grep -v ^$ | sed -n "s/\s\+//;/^#/d;p" ` && eval "$INFO"
  echo $INFO

  NAME=${f#*/.cron_unidump.d/}
  NAME=${NAME%%.conf}

  fileBaseDir=${fileDir:-$G_fileBaseDir}
  dbBaseDir=${dbDir:-$G_dbBaseDir}
  logBaseDir=${logDir:-$G_logBaseDir}

  necessaryDirectory $fileBaseDir $dbBaseDir $logBaseDir

  # ------------------
  # Backup files
  # ------------------

  # @TODO 增加清除条件

  if [ $SOURCE -a -d $SOURCE ]; then
    TARGET=$fileBaseDir/$NAME-$dateStrSuffix.tar.bz2
    snapFile=$logBaseDir/snapshot-$NAME-incremental
    monthSnapFile=$snapFile"-monthBase"
    logFileName=$NAME-$dateStrSuffix.log
    logFile=$logBaseDir/$logFileName

    #@TODO Add verbose to tar command -v
    fileBackupCommand="tar -g $snapFile -jpPc -f $TARGET $SOURCE $EXCLUDE"

    echo "------------------"$NAME"-------------------------" >> $logFile
    echo "Begin: "$dateStr >> $logFile
    echo $fileBackupCommand >> $logFile

    # Begin: Move incremental snapshot file to log every Sunday
    # Then without a snapshot file, tar make full backup every week.
    if [ "$(date +%d)" = "01" ] || [ "$dateOfRemovalSnapshot" = "ALL" ]; then
      [ -f $snapFile ] && mv $snapFile $snapFile-$(date +"%y%m%d").log
      $fileBackupCommand
      cp $snapFile $monthSnapFile
      if [ $dateOfRemovalSnapshot = "ALL" ]; then
        removalString="ALL"
      else
        removalString="Recreate month snapshot file "
      fi
      echo "REBASE STATUS::"$removalString >> $logFile
    else
      if [ -f $monthSnapFile ]; then
        # back day snapshot log
        [ -f $snapFile ] && mv $snapFile $snapFile-$(date +"%y%m%d").log
        cp $monthSnapFile $snapFile
        $fileBackupCommand
      else
        $fileBackupCommand
        # Add month basic snapshot
        cp $snapFile $monthSnapFile
      fi
    fi

    if [ $? = "0" ]; then
      backInfo="Backup successful!"
      chown $fileOwn $TARGET
    else
      backInfo="Backup failed! Error #"$?
    fi
    echo $backInfo
    echo $backInfo >> $logFile

    echo "End: "$(date +"%y-%m-%d %H:%M:%S") >> $logFile

    cp $logFile $fileBaseDir/
    chown $fileOwn $fileBaseDir/$logFileName
    echo "----------------------------------------------------" >> $logFile
  fi

  # ------------------
  # Mysql 
  # ------------------
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

  # 没有设置DBNAME
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
    alertMsg "Please check dbname name in "$f "$DBNAME is non-exist"
  fi

  # 检查库中，所有的表引擎与配置文件设置一致
  CHECKTYPE=true
  DBENGINE_UPPERCASE=$(echo $DBENGINE | tr '[a-z]' '[A-Z]');

  for tbl in $DB_TABLE_NAMES ; do
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

  if [ ! $CHECKTYPE ]; then
    alertMsg "Type is error" "Body"
  fi

  # Start backup
  startCommentLine 32m "Backing up MySQL database $DBNAME on $DBHOST..."
  dbBackDir=$dbBaseDir/$DBNAME
  dbBackDir_date=$dbBackDir/$dateStr
  if [ ! -d $dbBackDir_date ]; then
    commentLine 32m "Creating $dbBackDir_date for $DBNAME..."
    mkdir -p $dbBackDir_date
  fi

  test $DBHOST == "localhost" && server=`hostname -f` || server=$DBHOST

  case $DBENGINE in
    "myisam")
      # mysqlhotcopy
      C="sudo $myHotcopy -u $DBUSER -p $DBPASS --addtodest $DBNAME$DBOPTIONS $dbBackDir_date";;
    "mydumper")
      # mydumper
      C="$myDumper -o $dbBackDir_date -r 10000 -c -e -u $DBUSER -p $DBPASS -B $DBNAME $DBOPTIONS";;
    "mysqldump")
      # mysqldump
      C="$mysqlDump -h $DBHOST --user=$DBUSER --password=$DBPASS --add-drop-table $DBOPTIONS $DBNAME $DBSQLDUMP_TABLES -r$dbBackDir_date/backup.sql";;
  esac
  commentLine 33m "Command: $C"
  commandMsg=$($C)
  echo $commandMsg

  # Check backup
  BAK_FILENAME=$DBNAME-$dateStrSuffix.tar.gz
  BAK_FILEPATH=$dbBackDir/$BAK_FILENAME

  # 是否存在有效备份
  if [ -r $dbBackDir_date ] && [ ! -z "$(ls $dbBackDir_date)" ]; then
    tar -czPf $BAK_FILEPATH $dbBackDir_date
    sudo rm -rf $dbBackDir_date

    # if you have the mail program 'mutt' installed on
    # your server, this script will have mutt attach the backup
    # and send it to the email addresses in $EMAILS
    if  [ $DBMAIL = "y" ]; then
      BODY="Your backup is ready! \n\n"
      BODY=$BODY`cd $dbBackDir; md5sum $BAK_FILEPATH;`
      ATTACH=` echo -n "-a $BAK_FILEPATH "; `

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

  # unset variables
  # files
  unset NAME SOURCE TARGET EXCLUDE

  # mysql
	unset DBHOST DBUSER DBPASS
  unset DBENGINE DBNAME DBMAIL
  unset DBMAILTO DBSQLDUMP_TABLES
done
