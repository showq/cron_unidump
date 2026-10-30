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
  local host=$1
  local user=$2
  local pass=$3
  local command=$4
  local mysql_opts=""

  # If using MySQL defaults file (more secure)
  if [[ -n "$MYSQL_DEFAULTS_FILE" && -f "$MYSQL_DEFAULTS_FILE" ]]; then
    echo $(mysql --defaults-file="$MYSQL_DEFAULTS_FILE" -h "$host" -Bse "$command");
  else
    # Fallback to password parameter (less secure)
    echo $(mysql -h "$host" --user="$user" --password="$pass" -Bse "$command");
  fi
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

# Unified logging function
function logMsg(){
  local level=$1
  local message=$2
  local timestamp=$(date +'%Y-%m-%d %H:%M:%S')

  # Log to file if LOG_FILE is set
  if [[ -n "$LOG_FILE" ]]; then
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
  fi

  # Also display based on level
  case $level in
    'ERROR')
      alertMsg "$message"
      ;;
    'WARN')
      noticeMsg "$message"
      ;;
    'INFO')
      commentLine 'notice' "$message"
      ;;
  esac
}
# check of the directory exists
# if not, create it
function createDirectory(){
  if [ ! -d "$1" ]; then
    mkdir -p "$1"
    if [ -d "$1" ]; then
      successMsg "Successfully create the directory: $1"
    else
      alertMsg "Failed to create directory: $1"
      exit 1
    fi
  fi
}
# $1 $fileBaseDir
# $2 $dbBackDir
# $3 $logBaseDir
function necessaryDirectory(){

  createDirectory "$1"
  createDirectory "$2"
  createDirectory "$3"

  if [ ! -d "$1" ] || [ ! -d "$2" ] || [ ! -d "$3" ]; then
    alertMsg "Miss required directory" "Miss required directory, Please manually create"
  fi
}
#
function unidump_initEnv(){
  # install tip
  CONFIG="$HOME/.cron_unidump.conf"
  [ -f "$CONFIG" ] && . "$CONFIG" || die "Could not load configuration file ${CONFIG}! You can run ./cron_unidump.sh install"
  configDir="$HOME/.cron_unidump.d"
  fileOwn=${fileOwn:-${BACKUP_FILEOWN}}
}

# Validate configuration
function unidump_validate_config(){
  local errors=0

  # Check required tools
  if [[ -z "$myDumper" ]] && [[ -z "$mysqlDump" ]] && [[ -z "$myHotcopy" ]]; then
    alertMsg "No backup tools found" "Please install mydumper, mysqldump, or mysqlhotcopy"
    ((errors++))
  fi

  # Check if MySQL is accessible
  if [[ -n "$MYSQL_DEFAULTS_FILE" && -f "$MYSQL_DEFAULTS_FILE" ]]; then
    if ! mysql --defaults-file="$MYSQL_DEFAULTS_FILE" -e "SELECT 1;" > /dev/null 2>&1; then
      alertMsg "MySQL connection failed" "Please check your credentials in $MYSQL_DEFAULTS_FILE"
      ((errors++))
    fi
  elif [[ -n "$BACKUP_PASS" && "$BACKUP_PASS" != "YOUR_PASSWORD_HERE" ]]; then
    if ! mysql -h "$BACKUP_HOST" -u "$BACKUP_USER" -p"$BACKUP_PASS" -e "SELECT 1;" > /dev/null 2>&1; then
      alertMsg "MySQL connection failed" "Please check your credentials in config file"
      ((errors++))
    fi
  fi

  if [[ $errors -gt 0 ]]; then
    exit 1
  fi

  successMsg "Configuration validation passed"
}
# ------------------
# Check mysql config
# ------------------
function unidump_backup_db_check(){
  # Invoke default settings
  DBHOST=${DBHOST:-${BACKUP_HOST}}
  DBUSER=${DBUSER:-${BACKUP_USER}}
  DBPASS=${DBPASS:-${BACKUP_PASS}}
  MYSQL_DEFAULTS_FILE=${MYSQL_DEFAULTS_FILE:-${BACKUP_MYSQL_DEFAULTS_FILE}}
  DBENGINE=${DBENGINE:-"myisam"}
  DBNAME=${DBNAME//,/ }
  DBMAIL=${DBMAIL:-${BACKUP_MAIL}}
  DBMAILTO=${DBMAILTO:-${BACKUP_MAILTO}}
  DBOPTIONS=${DBOPTIONS:-""}
  DBSQLDUMP_TABLES=${DBSQLDUMP_TABLES:-""}

  CHECK_RESULT=true

  # Check if MySQL credentials are configured
  if [[ -z "$MYSQL_DEFAULTS_FILE" ]] && [[ -z "$DBPASS" || "$DBPASS" == "YOUR_PASSWORD_HERE" ]]; then
    alertMsg "MySQL credentials not configured" "Please set BACKUP_PASS in config or create MySQL defaults file"
    CHECK_RESULT=false
    exit 1
  fi

  # 没有设置DBNAME
  if [ -z "$DBNAME" ]; then
    DBS=$(mysqlCommand "$DBHOST" "$DBUSER" "$DBPASS" "Show databases;")
    TITLE="Creating list of all your databases... \n\n"
    BODY="Please modify config file, Usage "$DBS
    alertMsg "$TITLE" "$BODY"
    CHECK_RESULT=false
  fi

  # Fetch all tables from databases
  DB_TABLE_NAMES=$(mysqlCommand "$DBHOST" "$DBUSER" "$DBPASS" "use $DBNAME; show tables;")

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
    tblENGINE=$(mysqlCommand "$DBHOST" "$DBUSER" "$DBPASS" "$myCommand")

    tblENGINE_UPPERCASE=$(echo "$tblENGINE" | tr '[a-z]' '[A-Z]');

    if [[ "$tblENGINE_UPPERCASE" != "$DBENGINE_UPPERCASE" ]]; then
      CHECKTYPE=false
      break;
    fi
  done

  if [ "$CHECKTYPE" = false ]; then
    TITLE="table engine have differences on database "$DBNAME
    BODY="You can change the table engine to "$DBENGINE_UPPERCASE
    alertMsg $TITLE $BODY
    CHECK_RESULT=false
  fi

  if [ "$CHECK_RESULT" = false ]; then
    exit 1
  fi
}
#
#
function unidump_backup_db(){
  # Start backup database
  commentLine 'notice' "------------------ DB begin"
  commentLine 'notice' "Backing up MySQL database $DBNAME on $DBHOST..."
  dbBackDir=$dbBaseDir
  dbBackDir_date=$dbBackDir/$dateStr
  if [ ! -d $dbBackDir_date ]; then
    commentLine 'notice' "Creating $dbBackDir_date for $DBNAME..."
    mkdir -p $dbBackDir_date
  fi

  test "$DBHOST" == "localhost" && server=$(hostname -f) || server=$DBHOST

  # Build MySQL connection options
  if [[ -n "$MYSQL_DEFAULTS_FILE" && -f "$MYSQL_DEFAULTS_FILE" ]]; then
    MYSQL_OPTS="--defaults-file=$MYSQL_DEFAULTS_FILE"
  else
    MYSQL_OPTS="-u $DBUSER --password=$DBPASS"
  fi

  case $DBENGINE in
    "myisam")
      # mysqlhotcopy
      if [[ -n "$MYSQL_DEFAULTS_FILE" ]]; then
        alertMsg "mysqlhotcopy doesn't support --defaults-file" "Please use password in config or switch to mydumper"
        exit 1
      fi
      dumpCommand="sudo $myHotcopy -u $DBUSER -p $DBPASS --addtodest $DBNAME$DBOPTIONS $dbBackDir_date";;
    "mysqldump")
      # mysqldump
      dumpCommand="$mysqlDump -h $DBHOST $MYSQL_OPTS --add-drop-table $DBOPTIONS $DBNAME $DBSQLDUMP_TABLES -r$dbBackDir_date/backup.sql";;
    *)
      # mydumper
      dumpCommand="$myDumper -o $dbBackDir_date -r 10000 -c -e $MYSQL_OPTS -B $DBNAME $DBOPTIONS";;

  esac

  commentLine 'notice' "Command: $dumpCommand"
  if ! $dumpCommand; then
    alertMsg "Database backup failed" "Command: $dumpCommand"
    exit 1
  fi
  commentLine 'notice' "Command: End"
  # Clear DBNAME backspace
  DBNAME=${DBNAME// /_}

  # Check backup
  BAK_FILENAME="DB-"$DBNAME-$dateStrSuffix.tar.gz
  BAK_FILEPATH=$dbBackDir/$BAK_FILENAME

  # Mail 发送
  # 是否存在有效备份
  if [ -r $dbBackDir_date ] && [ ! -z "$(ls $dbBackDir_date)" ]; then
    # Create tar archive
    if ! tar -czPf $BAK_FILEPATH $dbBackDir_date; then
      alertMsg "Failed to create tar archive" "$BAK_FILEPATH"
      exit 1
    fi

    # Verify tar archive
    if ! tar -tzf $BAK_FILEPATH > /dev/null 2>&1; then
      alertMsg "Backup verification failed" "$BAK_FILEPATH is corrupted"
      rm -f $BAK_FILEPATH
      exit 1
    fi

    successMsg "Backup verified successfully" "$BAK_FILEPATH"

    #解压时 tar -zvjPf .tar.bz2
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
  INTERVAL_DAYS=${INTERVAL_DAYS:-${BACKUP_INTERVAL_DAYS}}

  if [ $SOURCE -a -d $SOURCE ]; then
    commentLine 32m "------------------ File backup begin"
    snapFile=$logBaseDir/snapshot-$NAME-incremental
    intervalSnapFile=$snapFile"-intervalBase"
    logFileName=$NAME-$dateStrSuffix.log
    logFile=$logBaseDir/$logFileName
    snapDate=$(date +"%y%m%d")

    # FILE_MODE (per conf) / BACKUP_FILE_MODE (global):
    #   incremental  - each run only contains changes since the previous run (default)
    #   differential - each run contains all changes since the last full backup
    # A full backup is made when the base snapshot is missing or older than INTERVAL_DAYS.
    FILE_MODE=${FILE_MODE:-${BACKUP_FILE_MODE:-incremental}}

    fullBackup=true
    if [[ -f $intervalSnapFile ]]; then
      t1=$(stat -c %Y $intervalSnapFile 2>/dev/null)
      t2=$(date -d "$INTERVAL_DAYS days ago" +%s 2>/dev/null)
      if [[ -n "$t1" ]] && [[ -n "$t2" ]] && [[ $t1 -ge $t2 ]]; then
        fullBackup=false
      fi
    fi
    # An incremental chain also needs the snapshot left by the previous run
    if [[ $fullBackup = false && $FILE_MODE = incremental && ! -f $snapFile ]]; then
      fullBackup=true
    fi

    if [ "$fullBackup" = true ]; then
      backupType=full
    elif [ "$FILE_MODE" = differential ]; then
      backupType=diff
    else
      backupType=inc
    fi

    # Type suffix in the name: restore = latest *-full + every later *-inc in order
    TARGET=$fileBaseDir/"FILE-"$NAME-$dateStrSuffix-$backupType.tar.bz2

    fileBackupCommand="tar -g $snapFile -jpPc -f $TARGET $SOURCE ${EXCLUDE[@]}"
    if [[ -d $EXTRA_SOURCE ]]; then
      fileBackupCommand="$fileBackupCommand $EXTRA_SOURCE"
    fi

    commentLine 33m "File backup ($backupType) command: $fileBackupCommand"

    echo "------------------"$NAME"-------------------------" >> $logFile
    echo "Begin: "$dateStr >> $logFile
    echo "Type: $backupType (mode=$FILE_MODE, full every $INTERVAL_DAYS days)" >> $logFile
    echo $fileBackupCommand >> $logFile

    # Keep the previous snapshot as history and as rollback point
    [ -f $snapFile ] && cp -p $snapFile $snapFile-$snapDate.log
    case $backupType in
      full) rm -f $snapFile ;;
      diff) cp $intervalSnapFile $snapFile ;;
      inc)  ;; # continue from the snapshot of the previous run
    esac

    nice -n 10 ionice -c2 -n7 $fileBackupCommand
    rc=$?

    # tar rc 1 = some files changed while being read; the archive is still usable
    if [ $rc -le 1 ]; then
      if [ $backupType = full ]; then
        cp $snapFile $intervalSnapFile
      fi
      backInfo="Backup successful! ($backupType, tar rc=$rc)"
      sudo chown $fileOwn $TARGET
    else
      # Roll the snapshot back so the next run does not skip these changes
      if [ -f $snapFile-$snapDate.log ]; then
        cp -p $snapFile-$snapDate.log $snapFile
      else
        rm -f $snapFile
      fi
      backInfo="Backup failed! ($backupType) Error #$rc"
    fi
    commentLine 'notice' "$backInfo"
    echo $backInfo >> $logFile

    echo "End: "$(date +"%y-%m-%d %H:%M:%S") >> $logFile

    # Remove backup directory log
    # cp $logFile $fileBaseDir/
    # sudo chown $fileOwn $fileBaseDir/$logFileName
    echo "----------------------------------------------------\n" >> $logFile
    commentLine 'notice' "------------------ File backup complete"
  fi
  # unset variables
  unset NAME SOURCE TARGET EXCLUDE FILE_MODE
}

function unidump_readConfig(){
  confFile="$configDir/$1.conf"

  if [[ ! -f $confFile ]]; then
    # 配置文件不存在.你可以使用命令[./cron_unidump.sh add name]增加一个配置文件。
    alertMsg "Config file ${confFile} is no exists" "You can use [add] command"
    exit 1
  fi

  INFO=`cat $confFile | grep -v ^$ | sed -n "s/\s\+//;/^#/d;p" ` && eval "$INFO"
  NAME=${confFile#*/.cron_unidump.d/}
  NAME=${NAME%%.conf}

  fileBaseDir=${fileDir:-$DEFAULT_fileBaseDir}/$NAME
  dbBaseDir=${dbDir:-$DEFAULT_dbBaseDir}/$NAME
  logBaseDir=${logDir:-$DEFAULT_logBaseDir}/$NAME

  necessaryDirectory "$fileBaseDir" "$dbBaseDir" "$logBaseDir"
}

#
function unidump_backup(){
  unidump_readConfig $2
  startCommentLine 'notice' "Start processing based on $confFile"
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

# 清除多余数据库备份
function unidump_clear_db(){
  read -p "Do you confirm delete database backup file ? [y/n]:" confirm
  if [[ $confirm = 'n' ]]; then
    exit 1;
  else
    # if  [ $DBDELETE = "y" ]; then
     OLDDBS=`cd $BACKDIR; find . -name "*-mysqlbackup.sql.gz" -mtime +$2`
     REMOVE=`for file in $OLDDBS; do echo -n -e "delete ${file}\n"; done`

    #  cd $BACKDIR; for file in $OLDDBS; do rm -v ${file}; done
    if  [ $2 = "1" ]; then
     echo "Yesterday's backup has been deleted."
    else
     echo "The backups from $2 days ago and earlier have been deleted."
    fi
  fi
}

function unidump_is_exists_file(){
  if [[ -f $1 ]]; then
    alertMsg "Duplicate name" "$1 is exists, Please use other name"
    exit 1;
  fi
}
function unidump_non_exists_file(){
  if [[ ! -f $1 ]]; then
    alertMsg "Config non exists" "$1 is non exists, Please use add name"
    exit 1;
  fi
}

#######################################
# Variables
#######################################
PATH="$PATH:/usr/local/bin"
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
DEFAULT_fileBaseDir=/var/www/html/backup
# database
DEFAULT_dbBaseDir=/var/www/html/backup
# log
DEFAULT_logBaseDir=/var/log/backup

# date format that is appended to filename
dateStr=$(date -u +'%F-%T')
dateStrSuffix=${dateStr//\:/-}

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

if [[ $1 != "install" ]]; then
  unidump_initEnv
fi

confFile="$HOME/.cron_unidump.d/$2.conf"

case $1 in
  'install')
    glob_conf="$HOME/.cron_unidump.conf"
    if [[ -f $glob_conf ]]; then
      alertMsg "It is installed" "Has been installed, please do not repeat installation"
      exit 1
    fi
    # Copy global config, set custom directory
    cp $initDir/cron_unidump.conf $glob_conf
    createDirectory $HOME/.cron_unidump.d
    cp $initDir/example.eg $HOME/.cron_unidump.d/example.eg

    sudo chmod +x $initDir/cron_unidump.sh

    # @TODO: Add to /usr/bin
    # ln -s $initDir/
    ln -s $initDir/cron_unidump.sh /usr/bin/cron_unidump

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
  'list')
    # --all
    commentLine 'success' "Current config file:"
    # @TODO: 可以在配置文件中增加描述，在显示时。便于阅读
    for i in $HOME/.cron_unidump.d/*.conf; do
      i=${i#*/.cron_unidump.d/}
      echo ${i%%.conf}
    done

    ;;
  'add')
    # Add new conf
    unidump_is_exists_file $confFile
    cp $HOME/.cron_unidump.d/example.eg $confFile
    vim $confFile

    successMsg 'Success' 'Successfully created $2, You must check the file and change it to real variables'

    ;;
  'edit')
    unidump_non_exists_file $confFile
    # commentLine 'success' "You edit config file that you use the code editor "
    vim "$configDir/$2.conf"

    ;;
  'show')
    unidump_non_exists_file $confFile
    commentLine 'success' "The following content is the config file [${confFile}] info"
    cat $confFile

    ;;

  'backup')
    # db, file, all
    unidump_backup $2 $3

    ;;
  'restore')
    # Required args
    # ./cron_unidump.sh restore [name] [date]
    # @TODO 已支持可选文件列表。需要控制显示数量。
    # 还要实现恢复指定数据库的功能
    noticeMsg "Notice:" "Only support database restore!";
    unidump_readConfig $2

    dbList='Please select following file:'
    dbArr=()
    i=0
    for file in $dbBaseDir/$2/*; do
      dbList="$dbList
$(($i+1)) )$file"
      dbArr[i]=$file
      i=$(($i+1))
    done

    read -p "$dbList
:" selectNum
    selectFile=${dbArr[$selectNum]}

    unidump_restore $2 $selectFile

    ;;
  'clear_db')
    # Clear database
    unidump_clear_db $2 $3

    ;;

  'check')
    #check config file
    unidump_validate_config
    successMsg "Configuration check completed"

    ;;
  'help')
    commentLine "alert" "The command support is upcoming!"

    ;;
  *)
    commentLine "alert" "Only support: install, uninstall, add, backup, restore, list, edit, show, check"
    ;;
esac



# ln -s ~/scripts/cron_unidump/cron_unidump.sh /usr/bin/cron_unidump
