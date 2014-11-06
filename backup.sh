#!/bin/bash
# =========================================================
# LogFileName=backup-incremental-$(date +"%y%m%d").log
# LogFile=/var/log/backup/$LogFileName
# =========================================================
PATH=/bin:/usr/bin:/sbin:/usr/sbin; export PATH
#basefile1=$basedir/mysql-$(date +%Y%m%d)-$(date +%H%M).tar.bz2
#basefile2=$basedir/cgi-bin.$(date +%Y%m%d).tar.bz2

# Initialize variables
basedir=/var/backup/files
backupLogDir=/var/log/backup
# mysqlrootpw='Mg#2013'
mysqlrootpw='liuyanjun'
chownName=vagrant:vagrant

# Check required directory
if [ ! -d "$basedir" ]; then
  sudo mkdir $basedir
  sudo chown $chownName $basedir
fi
if [ ! -d "$backupLogDir" ]; then
  sudo mkdir $backupLogDir
  sudo chown $chownName $backupLogDir
fi

#=============== Function Begin =========================
function SetEnv(){
  baktarget=$basedir/$bakName-$(date +%Y%m%d)-$(date +%H%M).tar.bz2
  snapfile=/var/log/backup/snapshot-$bakName-incremental
  monthSnapFile=$snapfile"-monthBase"
  LogFileName=$bakName-$(date +%Y%m%d).log
  LogFile=/var/log/backup/$LogFileName
  touch $LogFile
}

# Backup directory
function fileBackUp(){
  SetEnv

  # -v
  fileBackupCommand="tar -g $snapfile -jpc -f $baktarget $bakSource $excludepath"

  echo "------------------"$bakName"-------------------------" >> $LogFile
  echo "Begin: "$(date +"%y-%m-%d %H:%M:%S") >> $LogFile
  echo $fileBackupCommand >> $LogFile

  # Begin: Move incremental snapshot file to log every Sunday
  # Then without a snapshot file, tar make full backup every week.
  if [ $(date +%d) = '01' ] || [ $dateOfRemovalSnapshot = "ALL" ]; then
    [ -f $snapfile ] && mv $snapfile $snapfile-$(date +"%y%m%d").log
    $fileBackupCommand
    cp $snapfile $monthSnapFile
    if [ $dateOfRemovalSnapshot = "ALL" ]; then
      echo "RemovalString = ALL" >> $LogFile
    fi
  else
    if [ -f $monthSnapFile ]; then
      # back day snapshot log
      [ -f $snapfile ] && mv $snapfile $snapfile-$(date +"%y%m%d").log
      cp $monthSnapFile $snapfile
      $fileBackupCommand
    else
      $fileBackupCommand
      # Add month basic snapshot
      cp $snapfile $monthSnapFile
    fi
  fi
  # End Move incremental snapshot

  if [ $? = "0" ]; then
    backInfo="Backup successful!"
    chown $chownName $baktarget
  else
    backInfo="Backup failed! Error #"$?
  fi
  echo $backInfo
  echo $backInfo >> $LogFile

  echo "End: "$(date +"%y-%m-%d %H:%M:%S") >> $LogFile

  cp $LogFile $basedir/
  chown $chownName $basedir/$LogFileName
  echo "----------------------------------------------------" >> $LogFile
}

function mysqlBackUp(){
  SetEnv

  bakTime=$(date +"%y%m%d-%H%M")
  mysqlName=MySQL-DB-$mysqldb-$bakTime.sql
  mysqlTarget=$basedir/$mysqlName
  LogFileName=MySQL-DB-$mysqldb-$bakTime.log
  LogFile=/var/log/backup/$LogFileName

  echo "------------------"$mysqlName"-------------------------" >> $LogFile
  echo "Begin: "$(date +"%y-%m-%d %H:%M:%S") >> $LogFile

  mysqldump -u root -p$mysqlrootpw $1 > $mysqlTarget

  if [ $? = "0" ]
  then
    echo "Mysql $mysqlName backup successful!" >> $LogFile
    echo "Mysql $mysqlName backup successful!"
    chown $chownName $mysqlTarget
  else
    echo "Mysql $mysqlName backup failed! Error #"$? >> $LogFile
    echo "Mysql $mysqlName backup failed!"
  fi
  echo "End: "$(date +"%y-%m-%d %H:%M:%S") >> $LogFile

  chown $chownName $mysqlTarget
  cp $LogFile $basedir/
  chown $chownName $basedir/$LogFileName
}
#================Function End ===============================

#### 1. mandarin garden files backup
bakName=mg
bakSource=/vagrant_data/drupal
#excludePath="--exclude=$bakSource/sites/default/files/ipa"
excludePath=""
dateOfRemovalSnapshot='Sun' #
fileBackUp

#### 2. MySQL datafile
#bakName=mysqlmg
#bakSource=/var/lib/mysql
#excludePath="--exclude=$bakSource/mysql.sock"
#dateOfRemovalSnapshot='ALL' #don't use snapshot for mysql backup at all.
#fileBackUp

#### 3.  mysqldump
# mysqlBackUp "-B mysql unicom_drupal"
