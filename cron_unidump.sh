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
#  此脚本会读取$HOME/.cron_unidump.d目录下的[.*].conf的信息，并执行命令
#
#######################################
# for debug
# trap 'echo "before execute line:$LINENO, OPTIONS=${OPTIONS[@]}"' DEBUG
#######################################

#######################################
# Functions
#######################################
#
function die(){
  echo >&2 "$@"
  exit 1
}
#
function mysqlCommand(){
  echo `mysql -h $1 --user=$2 --password=$3 -Bse "$4"`;
}
function getColorByType(){
  case $1 in
    'alert')
      COLOR="31m"
      ;;
    'notice')
      COLOR="34m"
      ;;
    'success')
      COLOR="32m"
      ;;
  esac
}
#
function startCommentLine(){
  getColorByType $1
  echo -e "\033[$COLOR#################### \033[0m"
  echo -e "\033[$COLOR# $2 \033[0m"
}
#
function commentLine(){
  getColorByType $1
  echo -e "\033[$COLOR# $2 \033[0m"
}
#
function endCommentLine(){
  getColorByType $1
  # echo -e "\033[$1##$2 \033[0m"
  echo -e "\033[$COLOR#################### \033[0m"
  echo " "
}
#
function commonMsg(){
  startCommentLine "$3" "$1"
  if [[ -n $2 ]]; then
    commentLine "$3" "$2"
  fi
  endCommentLine "$3"
}
#
function alertMsg(){
  commonMsg "$1" "$2" 'alert'
}
#
function noticeMsg(){
  commonMsg "$1" "$2" 'notice'
}
#
function successMsg(){
  commonMsg "$1" "$2" 'success'
}
# check of the directory exists
# if not, create it
function createDirectory(){
  if [ ! -d $1 ]; then
    mkdir -p $1
    if [ -d $1 ]; then
      successMsg "Successfully create the directory: $1"
    fi
  fi
}
# $1 $fileBaseDir
# $2 $dbBackDir
# $3 $logBaseDir
function necessaryDirectory(){

  createDirectory $1
  createDirectory $2
  createDirectory $3

  if [ ! -d $1 ] || [ ! -d $2 ] || [ ! -d $3 ]; then
    alertMsg "Miss required directory" "Miss required directory, Please manually create"
  fi
}
#
function unidump_initEnv(){
  # install tip
  CONFIG="$HOME/.cron_unidump.conf"
  [ -f "$CONFIG" ] && . "$CONFIG" || die "Could not load configuration file ${CONFIG}! You can run ./cron_unidump.sh install"
  configDir="$HOME/.cron_unidump.d"
}
# ------------------
# Check mysql config
# ------------------
function unidump_backup_db_check(){
  # Invoke default settings
  DBHOST=${DBHOST:-${BACKUP_HOST}}
  DBUSER=${DBUSER:-${BACKUP_USER}}
  DBPASS=${DBPASS:-${BACKUP_PASS}}
  DBENGINE=${DBENGINE:-"myisam"}
  DBNAME=${DBNAME}
  DBMAIL=${DBMAIL:-${BACKUP_MAIL}}
  DBMAILTO=${DBMAILTO:-${BACKUP_MAILTO}}
  DBOPTIONS=${DBOPTIONS:-""}

  DBSQLDUMP_TABLES=${DBSQLDUMP_TABLES:-""}

  CHECK_RESULT=true

  # 没有设置DBNAME
  if [ -z "$DBNAME" ]; then
    DBS=`mysqlCommand $DBHOST $DBUSER $DBPASS "Show databases;"`
    TITLE="Creating list of all your databases... \n\n"
    BODY="Please modify config file, Usage "$DBS
    alertMsg $TITLE $BODY
    CHECK_RESULT=false
  fi

  # Fetch all tables from databases
  DB_TABLE_NAMES=`mysqlCommand $DBHOST $DBUSER $DBPASS "use $DBNAME; show tables;"`

  # If DB_TABLE_NAMES is empty, DBNAME no exists
  if [ -z "$DB_TABLE_NAMES" ]; then
    alertMsg "Please check dbname name in $confFile $DBNAME is non-exist"
    CHECK_RESULT=false
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
    TITLE="table engine have differences on database "$DBNAME
    BODY="You can change the table engine to "$DBENGINE_UPPERCASE
    alertMsg $TITLE $BODY
    CHECK_RESULT=false
  fi

  if [[ ! $CHECK_RESULT ]]; then
    exit 1
  fi
}
#
#
function unidump_backup_db(){
  # Start backup database
  commentLine 'notice' "------------------ DB begin"
  commentLine 'notice' "Backing up MySQL database $DBNAME on $DBHOST..."
  dbBackDir=$dbBaseDir/$1
  dbBackDir_date=$dbBackDir/$dateStr
  if [ ! -d $dbBackDir_date ]; then
    commentLine 'notice' "Creating $dbBackDir_date for $DBNAME..."
    mkdir -p $dbBackDir_date
  fi

  test $DBHOST == "localhost" && server=`hostname -f` || server=$DBHOST

  case $DBENGINE in
    "myisam")
      # mysqlhotcopy
      dumpCommand="sudo $myHotcopy -u $DBUSER -p $DBPASS --addtodest $DBNAME$DBOPTIONS $dbBackDir_date";;
    "mydumper")
      # mydumper
      dumpCommand="$myDumper -o $dbBackDir_date -r 10000 -c -e -u $DBUSER -p $DBPASS -B $DBNAME $DBOPTIONS";;
    "mysqldump")
      # mysqldump
      dumpCommand="$mysqlDump -h $DBHOST --user=$DBUSER --password=$DBPASS --add-drop-table $DBOPTIONS $DBNAME $DBSQLDUMP_TABLES -r$dbBackDir_date/backup.sql";;
  esac

  commentLine 'notice' "Command: $dumpCommand"
  commandMsg=$($dumpCommand)
  commentLine 'notice' "$commandMsg"

  # Check backup
  BAK_FILENAME=$DBNAME-$dateStrSuffix.tar.gz
  BAK_FILEPATH=$dbBackDir/$BAK_FILENAME

  # Mail 发送
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

  commentLine 'success' "------------------ DB complete"
  commentLine 'success' "The database $DBNAME is backed up!"
  endCommentLine 'success'

  # @TODO record backup log

  # unset variables
  unset DBHOST DBUSER DBPASS
  unset DBENGINE DBNAME DBMAIL
  unset DBMAILTO DBSQLDUMP_TABLES
}
function unidump_backup_file(){
  # ------------------
  # Backup files
  # ------------------
  # @TODO 增加清除条件
  if [ $SOURCE -a -d $SOURCE ]; then
    commentLine 32m "------------------ File backup begin"
    TARGET=$fileBaseDir/$NAME-$dateStrSuffix.tar.bz2
    snapFile=$logBaseDir/snapshot-$NAME-incremental
    monthSnapFile=$snapFile"-monthBase"
    logFileName=$NAME-$dateStrSuffix.log
    logFile=$logBaseDir/$logFileName

    #@TODO Add verbose to tar command -v
    fileBackupCommand="tar -g $snapFile -jpPc -f $TARGET $SOURCE $EXCLUDE"

    commentLine 33m "File backup command: $fileBackupCommand"

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
    commentLine 'notice' "$backInfo"
    echo $backInfo >> $logFile

    echo "End: "$(date +"%y-%m-%d %H:%M:%S") >> $logFile

    cp $logFile $fileBaseDir/
    chown $fileOwn $fileBaseDir/$logFileName
    echo "----------------------------------------------------\n" >> $logFile
    commentLine 'notice' "------------------ File backup complete"
  fi
  # unset variables
  unset NAME SOURCE TARGET EXCLUDE
}
#
function unidump_backup(){

  confFile="$configDir/$2.conf"

  if [[ ! -f $confFile ]]; then
    # 配置文件不存在.你可以使用命令[./cron_unidump.sh add name]增加一个配置文件。
    alertMsg "Config file ${confFile} is no exists" "You can use [add name]"
    exit 1
  fi

  INFO=`cat $confFile | grep -v ^$ | sed -n "s/\s\+//;/^#/d;p" ` && eval "$INFO"
  NAME=${confFile#*/.cron_unidump.d/}
  NAME=${NAME%%.conf}

  startCommentLine 'notice' "Start processing based on $confFile"

  fileBaseDir=${fileDir:-$DEFAULT_fileBaseDir}
  dbBaseDir=${dbDir:-$DEFAULT_dbBaseDir}
  logBaseDir=${logDir:-$DEFAULT_logBaseDir}

  necessaryDirectory $fileBaseDir $dbBaseDir $logBaseDir

  # backup type
  case $1 in
    'db')
      unidump_backup_db_check $2
      unidump_backup_db $2
      ;;
    'file')
      unidump_backup_file $2
      ;;
    'all')
      unidump_backup_db_check $2
      unidump_backup_db $2
      unidump_backup_file $2
      ;;
    *)
      alertMsg "" "Only accept db, file, all"
      ;;
  esac
  endCommentLine 'notice'
}

# @TODO
# $1 type
#   db, file, all
# $2 name
#   name
# $3 date
#   latest or date
function unidump_restore(){

  alertMsg 'Restore' 'Restore $1 at $2'
}

#######################################
# Variables
#######################################
# shell文件存放的根目录
initDir=${initDir:-`pwd`}

# 执行目录
# execDir=$(dirname $0)

# your mysql server's name
server=`hostname -f`

# your mysqlhotcopy
myHotcopy=$(which mysqlhotcopy)
# your mydumper
myDumper=$(which mydumper)
# your mysqldump
mysqlDump=$(which mysqldump)

########################################
# Basic backup file store directory
########################################
# file
DEFAULT_fileBaseDir=/var/backup/files
# database
DEFAULT_dbBaseDir=/var/backup/mysql
# log
DEFAULT_logBaseDir=/var/log/backup

# date format that is appended to filename
dateStr=$(date -u +'%F-%T')
dateStrSuffix=${dateStr//\:/-}

fileOwn='vagrant:vagrant'

#######################################
# Shell Body
#######################################
# install this shell scripts
# example:
# ./cron_unidump.sh install
# ./cron_unidump.sh add
# ./cron_unidump.sh backup $type $configName
# ./cron_unidump.sh restore $configName $date
# ./cron_unidump.sh list
# @TODO
# ./cron_unidump.sh edit $name
# ./cron_unidump.sh show $name
unidump_initEnv

case $1 in
  'install')
    # Copy global config, set custom directory
    glob_conf="$HOME/.cron_unidump.conf"
    if [[ -f $glob_conf ]]; then
      alertMsg "It is installed" "Has been installed, please do not repeat installation"
      exit 1
    fi

    cp $initDir/cron_unidump.conf
    createDirectory $HOME/.cron_unidump.d
    cp $initDir/example.eg $HOME/.cron_unidump.d/example.eg

    successMsg 'Success' 'Successfully installed'

    ;;
  'uninstall')
    read -p "Do you confirm to uninstall[y/n]:" confirm
    if [[ $confirm = 'y' ]]; then
      rm -r $HOME/.cron_unidump.d
      rm $HOME/.cron_unidump.conf
      successMsg 'Uninstalled' 'Successfully uninstalled'
    else
      successMsg 'Canceled' 'It is canceled'
    fi

    ;;
  'add')
    # Add new conf
    # @TODO: 如果配置文件重名增加判断
    #
    # @TODO: 文件的备份目录。数据库的参数等？
    cp $HOME/.cron_unidump.d/example.eg $HOME/.cron_unidump.d/$2.conf

    # @TODO: 增加crontab支持。直接进入crontab.提供必要参数
    #
    successMsg 'Success' 'Successfully created $2, You must check the file and change it to real variables'

    ;;
  'backup')
    # db, file, all
    unidump_backup $2 $3

    ;;
  'restore')
    # Required args
    # ./cron_unidump.sh restore [name] [date]
    # @TODO,显示一个列表。用户自己选择恢复时间。可以指定时间段
    unidump_restore $2 $3

    ;;
  'list')
    # --all
    commentLine 'success' "Current config file"
    # @TODO: 可以在配置文件中增加描述，在显示时。便于阅读
    for i in $HOME/.cron_unidump.d/*.conf; do
      i=${i#*/.cron_unidump.d/}
      echo ${i%%.conf}
    done

    ;;
  'edit')
    commentLine 'success' "You edit config file that you use the code editor "
    vi "$configDir/$2.conf"

    ;;
  'show')
    confFile="$configDir/$2.conf"
    commentLine 'success' "The following content is the config file [${confFile}] info"
    cat $confFile

    ;;
  'help')
    commentLine "alert" "The command support is upcoming!"

    ;;
esac