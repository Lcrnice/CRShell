#! /bin/sh

if [ -z $2 ]; then
  echo "Syntax: $0 <*m3u8_url> <*file_name> <ts_dir> <m3u8_dir> "
  exit 1
fi

M3U8_URL=$1
FNAME=$2
TS_DIR=$3
M3U8_DIR=$4


# configure default envionment variables
CURRENT_PATH=`pwd`
INFO_PATH="$CURRENT_PATH/log"
INFO_LOG="$INFO_PATH/info.log"
RETRY_COUNT=5
FFMPEG="ffmpeg"		# path of ffmpeg

if [ -n $TS_DIR ]; then
    TS_DIR="$CURRENT_PATH/ts"
fi
if [ -n $M3U8_DIR ]; then
    M3U8_DIR="$CURRENT_PATH"
fi

logger() {
    msg=$1
    echo "`date +%Y-%m-%d_%H:%M:%S` fname:$FNAME $msg" >> $INFO_LOG
}

download_ts() {
    retry=$1
    
    if [ ! -f $FNAME ]; then
      echo "$FNAME not exist"
      exit 2
    fi

    M3U8_NAME=`echo $M3U8_URL | awk -F'/' '{print $NF}'`
    echo m3u8 name: $M3U8_NAME in url
    #BASE_PATH=`echo $M3U8_URL | sed "s/$M3U8_NAME//"`
    BASE_PATH=`echo $M3U8_URL | awk -F'/' '{print $1"//"$3}'`
    echo base url path: $BASE_PATH
    
    for ts in `cat $FNAME | grep ".ts"`
    do
	ts_name=`echo $ts | awk -F '/' '{print $NF}'`
	ts_file="$TS_DIR/$ts_name"
	if [ -f $ts_file ]; then
	    echo "$ts_file already download, continue."
	    continue
	fi

	wget -x $BASE_PATH$ts -O $ts_file
	if [ $? != 0 ]; then
	    rm -f $ts_file
	    logger "download $ts failed. retry:$retry"

	    let "count=RETRY_COUNT-1"
	    if [ $retry = $count ]; then
		match_ts_in_m3u8 $ts $FNAME
	    fi

	    continue
	fi

	duration=`$FFMPEG -y -i $ts_file 2>&1|grep Duration|awk -F':' '{print $4+$3*60+$2*60*60}'`
	if [ -z $duration ]; then
	    rm -f $ts_file
	    logger "ts $ts duration is 0 , already remove. retry:$retry"

	    let "count=RETRY_COUNT-1"
	    if [ $retry = $count ]; then
		match_ts_in_m3u8 $ts $FNAME
	    fi

	    continue
	fi

	originsize=`curl --head "$BASE_PATH$ts" | grep "Content-Length" | awk -F': ' '{print $2}'`
	localsize=`stat --printf="%s" $ts_file`
	if [ $originsize -ne $localsize ]; then
	    logger "ts size error, download ts size:$localsize  url ts size:$originsize , retry:$retry"
	fi

    done
}

match_ts_in_m3u8() {
    ts=$1
    m3u8=$2
    tsline=`grep -n $ts $m3u8`

    if [ -z $tsline ]; then
	logger "can not mactch $ts when delete text."
    else
	extinfline=`echo $tsline | awk -F':' '{print $1-1}'`
	sed -i "/$ts/d" $m3u8 && sed -i "$extinfline d" $m3u8
	if [ $? = 0 ]; then
	    logger "already delete $ts and title at line $extinfline."
	else
	    logger "delete $ts and title failed."
	fi
    fi
}

generate_all_ts_txt() {
    ALL_TS_TXT="$M3U8_DIR/$FNAME.allts.txt"
    if [ -f $ALL_TS_TXT ]; then
        rm -f $ALL_TS_TXT
    fi

    for ts in $TS_DIR/*.ts;
    do 
	echo "file '$ts'" >> $ALL_TS_TXT; 
    done
}

convert_to_mp4() {
    ALL_TS="$M3U8_DIR/$FNAME.all.ts"
    #TARGET_MP4=`echo $FNAME | sed 's/m3u8/mp4/g'`
    TARGET_MP4="$FNAME.mp4" 
    # reference https://trac.ffmpeg.org/wiki/Concatenate
    $FFMPEG -y -f concat -safe 0 -i $ALL_TS_TXT -c copy $ALL_TS
    $FFMPEG -y -i $ALL_TS -c copy -bsf:a aac_adtstoasc -async 1 -movflags faststart $M3U8_DIR/$TARGET_MP4

    if [ $? != 0 ]; then
	logger "concat mp4 failed!!"
    else
	logger "create mp4 success."
    fi
}

retry_download_ts() {
    retry=0
    DOWNLOAD_COUNT=`ls $TS_DIR | wc -l`
    TS_COUNT=`cat $FNAME | grep ".ts" | wc -l`
    
    while [ $DOWNLOAD_COUNT -lt $TS_COUNT ] && [ $retry -lt $RETRY_COUNT ]; do
	if [ $retry -gt 1 ]; then
	    sleep 300
	fi
	echo "download >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> retry=$retry"

	download_ts $retry
    
	echo "ts dir count: `ls $TS_DIR | wc -l`"
	echo "m3u8 ts count: `cat $FNAME | grep ".ts" | wc -l`"
	((retry++));
	
	DOWNLOAD_COUNT=`ls $TS_DIR | wc -l`
	if [ $DOWNLOAD_COUNT -lt $TS_COUNT ] && [ $retry -eq $RETRY_COUNT ]; then
	    logger "download ts incomplete, download: $DOWNLOAD_COUNT tss: $TS_COUNT. "
	fi

	if [ $DOWNLOAD_COUNT -eq $TS_COUNT ]; then
	    logger "download all ts finish."
	fi
    done
}

# ---------------------------------------------------------

mkdir -p $M3U8_DIR
mkdir -p $TS_DIR
mkdir -p $INFO_PATH

wget $M3U8_URL -O $M3U8_DIR/$FNAME
cd $M3U8_DIR

retry_download_ts
generate_all_ts_txt
convert_to_mp4

rm -f $FNAME
rm -f $ALL_TS_TXT
rm -f $ALL_TS
rm -rf $TS_DIR
