#!/bin/bash
# Author:  yeho <lj2007331 AT gmail.com>

# Default Parameters
myIFS=":::"

IP=$1P
PORT=$2P
USER=$3
PASSWD=$4P
CONFIG_FILE=$5
SSHTIMEOUT=$6
SCPTIMEOUT=$7
BWLIMIT=$8

# 任意一台主机的任意一条命令失败都要反映到退出码：
# 原来无论成败都 exit 0，而 backup.sh 又是 `thread.sh | tee` 调用，失败被彻底吞掉，
# cron 每晚返回 0，远程备份停了也没人知道。
fail=0

while read eachline
do
  [ -z "`echo $eachline | grep -E '^com|^file'`" ] && continue

  myKEYWORD=`echo $eachline | awk -F"$myIFS" '{ print $1 }'`
  myCONFIGLINE=`echo $eachline | awk -F"$myIFS" '{ print $2 }'`

  if [ "$myKEYWORD"x == "file"x ]; then
    SOURCEFILE=`echo $myCONFIGLINE | awk '{ print $1 }'`
    DESTDIR=`echo $myCONFIGLINE | awk '{ print $2 }'`
    DIRECTION=`echo $myCONFIGLINE | awk '{ print $3 }'`
    ./mscp.exp $IP $USER $PASSWD $PORT $SOURCEFILE $DESTDIR $DIRECTION $BWLIMIT $SCPTIMEOUT

    if [ $? -ne 0 ]; then
      echo -e "\033[31mSCP Try Out All Password Failed\033[0m\n"
      fail=1
    fi

  elif [ "$myKEYWORD"x == "com"x ]; then
    ./mssh.exp $IP $USER $PASSWD $PORT "${myCONFIGLINE}" $SSHTIMEOUT
    if [ $? -ne 0 ]; then
      echo -e "\033[31mSSH Try Out All Password Failed\033[0m\n"
      fail=1
    fi

  else
    echo "ERROR: configuration wrong! [$eachline] "
    echo "       where KEYWORD should not be [$myKEYWORD], but 'com' or 'file'"
    echo "       if you dont want to run it, you can comment it with '#'"
    echo ""
    exit
  fi

done < $CONFIG_FILE

exit $fail
