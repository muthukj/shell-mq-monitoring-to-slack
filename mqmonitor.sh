#!/bin/bash
#@author : praveen_gundu
#load the properties file first
. /home/wmb/scripts/mqscript.properties
MQ_INSTALLATION_PATH="/opt/mqm/7.5_1"
prefix=""
apendingText=""

#set the QM name basis of the Host- better logic can be implemented
#check for the environment so that u check for the environment 
if [ "$HOSTNAME" == "" ]
	then
		prefix="D"
elif [ "$HOSTNAME" == "" ]
	then
		prefix="T"
else
		prefix=""
fi

# you've to define a generic function to post the messages to slack for each check performed.
# Method to post the message to slack.
#@ input: Check numner performed as an integer
function post_to_slack()
{
	case $1 in

		0)  # initial post
				curl -X POST --data-urlencode 'payload={"channel": "#channel_name", "username": "user_id", "text":
				"*\nHost:  *_'$HOSTNAME'_*               Enivornment: *_ '${prefix}'EV_*", "icon_emoji": ":ghost:"}' ur_slack_integration_url  --proxy proxy_if_any

			;;
		1) #memory check post
			curl -X POST --data-urlencode 'payload={"channel": "#channel_name", "username": "user_id", "text":"Memory Report: _*'$3'*_ CurrentSpace used is: _*'$2'*_ ", "icon_emoji": ":ghost:"}' slack_channel_integration_url  --proxy proxy_if_any
			;;
		2) #Qmanager check
			 curl -X POST --data-urlencode 'payload={"channel": "#channel_name", "username": "user_id", "text":"Qmanager Report:  _*'$2'*_  is: _*'$3'*_ ", "icon_emoji": ":ghost:"}' slack_channel_integration_url  --proxy proxy_if_any
			;;
		3) #echo listener check 
			 curl -X POST --data-urlencode 'payload={"channel": "#channel_name", "username": "user_id", "text":" listener for '$2' is down", "icon_emoji": ":ghost:"}' slack_channel_integration_url  --proxy proxy_if_any
                        ;;
		4) #channel instances crossed the threshold
                       curl -X POST --data-urlencode 'payload={"channel": "#channel_name", "username": "user_id", "text":"Channel Report: '$3' on '$2' is using '$4' instances!!", "icon_emoji": ":ghost:"}' slack_channel_integration_url  --proxy proxy_if_any
                        ;;
		5) #channel is inactive
                       curl -X POST --data-urlencode 'payload={"channel": "#channel_name", "username": "user_id", "text":"Channel Report: '$3' on '$2' is inactive it might or might not be an issue but good to check out!!", "icon_emoji": ":ghost:"}' slack_channel_integration_url  --proxy proxy_if_any
                        ;;
		6) #q depth crossed the threshold
                       curl -X POST --data-urlencode 'payload={"channel": "#channel_name", "username": "user_id", "text":"Queue Report: '$3' on '$2' is having '$4' messages  check corresponding activity service or DP!!", "icon_emoji": ":ghost:"}' slack_channel_integration_url  --proxy proxy_if_any
                        ;;
		7) #q depth crossed the threshold
                      curl -X POST --data-urlencode 'payload={"channel": "#channel_name", "username": "user_id", "text":"Channel Report: '$3' on '$2' is in retry status switch QM must have gone down go start it/them!!", "icon_emoji": ":ghost:"}' slack_channel_integration_url  --proxy proxy_if_any
                        ;;
		9) #echo  other checks
		  	
		   ;;
		*) #echo other checks
			
		   ;;
	esac

	
}   # end of post_to_slack

post_to_slack 0 #initial post with hostname and Environment

#start performing checks
#Check1 Check for the memory space on mqsi and mqm dirves if it crosses 70% push the notification
#function for drive space on server
#@ input: path where you want to check the memory space
function drive_space()
{
	DiskSpace=""
	DiskSpace="`df -h $1 |  awk '{print $4}' | grep % | sed -e 's/%//'`" #this will return the integer value of the memory
	echo "$DiskSpace"

}   # end of drive_space

mqsiDiskSpace=$(drive_space $"/var/mqsi") #drive space on mqsi
mqmDiskSpace=$(drive_space $"/var/mqm")   #drive space on mqm
rootSpace=`df -h | awk '{print $5}' | grep % | grep -v Use | sort -n | tail -1 | cut -d "%" -f1 -`


# now check if either of them crossed the threshould

if [ $mqsiDiskSpace -gt $memorythreshold ]
	then
		post_to_slack 1 $mqsiDiskSpace $mqsidrivemessage  #" var/mqsi drive crossed the memory threshould, check it out!"
fi
if [ $mqmDiskSpace -gt $memorythreshold ]
	then
		post_to_slack 1 $mqmDiskSpace $mqmdrivemessage #" var/mqm drive crossed the memory threshould, check it out!"
fi
if [ $rootSpace -gt $memorythreshold ]
	then
		post_to_slack 1 $rootSpace $rootdrivemessage # there's a drive which crossed threshould of 90% usage
fi

#memory check's been done now check for the QMs, check if they are responsive

qmarray=($(dspmq | awk '{ print $1 }' | cut -c 8- | sed -e 's/)//'))

#function to check the channel instance count
#@ input: QM name
function check_channel_instance_count_dp()
{
	channel="channel_name"
	dpchannel=`echo "DIS CHSTATUS($channel)" | runmqsc  $1 | awk '{ print $1 }' | grep AMQ`
	if echo "$dpchannel" | grep -q "8420";  #channel looks inactive report it
			then 
			post_to_slack 5 $1 $channel
	else #channel is active now check for the instances, u don't have to check for the retry status as it is SVRCONN
		    channelInstanceCount=`echo "DIS CONN(*) TYPE(CONN) CONNAME CHANNEL" | mqsc -e -m $1 -p width=1000 | grep $channel | wc -l`
			if [ $channelInstanceCount -gt $channelinstancethreshold ]
				then
				post_to_slack 4 $1 $channel $channelInstanceCount
				#post to slack that channel instances are high for this channel and QM
			fi
	fi
}
#function to check the ttcp listener of QM
#@ input: QM name
function check_mq_tcp_listener()
{
listener=`ps -ef|grep lsr | grep $1 |wc -l`
	if [ $listener -ne 1 ]
		then
		post_to_slack 3 $1
		#echo post to slack that listener is down for this QM
	fi
}
#function to check the channel status of QM
#@ input: QM name
function check_dp_mq_channels()
{
	dpchannel=`echo "DIS CHSTATUS(channel_name)" | runmqsc  $1 | awk '{ print $1 }' | grep AMQ`
		if echo "$dpchannel" | grep -q "8420";  #channel looks in active report it
			then 
			channel="channel_name"
			post_to_slack 4 $1 $channel
		fi
}
#function to check the channel status of QM
#@ input: QM name
function check_channel_instance_count_was()
{
	channel="channel_name"
	dpchannel=`echo "DIS CHSTATUS($channel)" | runmqsc  $1 | awk '{ print $1 }' | grep AMQ`
	if echo "$dpchannel" | grep -q "8420";  #channel looks inactive report it
			then 
			post_to_slack 5 $1 $channel
	else #channel is active now check for the instances, u don't have to check for the retry status as it is SVRCONN
		    channelInstanceCount=`echo "DIS CONN(*) TYPE(CONN) CONNAME CHANNEL" | mqsc -e -m $1 -p width=1000 | grep $channel | wc -l`
			if [ $channelInstanceCount -gt $channelinstancethreshold ]
				then
				post_to_slack 4 $1 $channel $channelInstanceCount
				#post to slack that channel instances are high for this channel and QM
			fi
	fi

}
#function to check the channel status of QM
#@ input: QM name
function check_mq_channels()
{
	#if its export qm u have to check sdr channels and if its is import Qm u have to check revr channels both to/from SM1
	if echo "$1" | grep -q "ME";
	then
	channel="channel_name"
	else
	channel="channel_name"
	fi
	dpchannel=`echo "DIS CHSTATUS($channel)" | runmqsc  $1 | awk '{ print $1 }' | grep AMQ`
	if echo "$dpchannel" | grep -q "8420";  #channel looks inactive report it
			then 
			post_to_slack 5 $1 $channel
	else #channel is active now check for the status, because if it is in retry state thats an issue
		    channelstatus=`echo "dis chstatus($channel)" | runmqsc $1 | grep STATUS | awk '{ print $2 }' | cut -c 8-|sed -e 's/)//'`
			# check if the channel is in retry state, if its then u have to start it 
			if echo "$channelstatus" | grep -q "RET"; # channel is in retry status
			then
			#stop and start the channel
			post_to_slack 7 $1 $channel	
			elif echo "$channelstatus" | grep -q "STOP"; # channel is in retry status
			then
			post_to_slack 7 $1 $channel	
			fi
	fi


}
#function to check the q depth
#@ input: QM name
function check_dp_in_queue_depth()
{
	# take the was input queues into an array 
	qarray=($(echo "dis ql(*)" | runmqsc $1 | grep DPW_IN | grep ECOM |  cut -c 10-|sed -e 's/)//'))
	#loop through each q and check the depth, if it crosses the threshold then report it
	for i in "${qarray[@]}"
	do
	  depth=`echo "dis ql($i) curdepth" | runmqsc $1 | grep CUR | awk '{ print $2 }'|cut -c 10-|sed -e 's/)//'`
	  if [ $depth -gt $qdepthlimit ]
				then
				post_to_slack 6 $1 $i $depth
	  fi
	done

}
#function to check the q depth
#@ input: QM name
function check_mq_queue_depth()
{
	# take the was input queues into an array , take only specific queues
	qarray=($(echo "dis ql(ACTREQ*)" | runmqsc $1 | grep ACTREQ |cut -c 10-|sed -e 's/)//'))
	#loop through each q and check the depth, if it crosses the threshold then report it
	for i in "${qarray[@]}"
	do
	  depth=`echo "dis ql($i) curdepth" | runmqsc $1 | grep CUR | awk '{ print $2 }'|cut -c 10-|sed -e 's/)//'`
	  if [ $depth -gt $qdepthlimit ]
				then
				post_to_slack 6 $1 $i $depth
	  fi
	done

}


#QMs are read into array now loop over and check if it is responsive
#function to check if Qms are responsive, function to be defined first before calling, thats how shell works :P
#@ input: QM name
function ping_qmgr()
{
# Test the operation of the queue manager. Result is 0 on success, non-zero on error.
echo "ping qmgr" | runmqsc $1 > /dev/null 2>&1  #write it to dev/null so it bounces back, then read it if it was responsive
qmresponded=$?
if [ $qmresponded -eq 0 ]
	then # ping succeeded
		 #post_to_slack 2 $1 #u don't have tp report this
	     #now that the QM is running , perform other checks like for channels and qdepths..etc
		if echo "$1" | grep -q "GX";  #check for different QMs
			then 
			check_mq_tcp_listener $1
			check_channel_instance_count_dp $1
			check_dp_in_queue_depth $1
		elif echo "$1" | grep -q "GC"; 
			then
			check_mq_tcp_listener $1
			check_channel_instance_count_was $1
			check_mq_queue_depth $1
		elif echo "$1" | grep -q "ME"; 
			then
			check_mq_tcp_listener $1
			check_mq_channels $1
		elif echo "$1" | grep -q "MI"; 
			then
			check_mq_tcp_listener $1
			check_mq_channels $1
		fi
		 #other QMs are not in scope for now
		 
	else # ping failed
		  # Don't condemn the queue manager immediately, it might be starting.
	  srchstr="( |-m)$1 *.*$"
	  cnt=`ps -ef | tr "\t" " " | grep strmqm | grep "$srchstr" | grep -v grep \
					| awk '{print $2}' | wc -l`

			if [ $cnt -gt 0 ]
			  then
				# It appears that the queue manager is still starting up, tolerate
				#echo "Queue manager '${QM}' is starting"
				post_to_slack 2 $1 $qmstrmessage
				#result=0
			  else
				# There is no sign of the queue manager starting
				#echo "Queue manager '${QM}' is not responsive"
				post_to_slack 2 $1 $qmnotrespmessage
				#result=$pingresult
			  fi
			  
fi

} 


for i in "${qmarray[@]}"
	do
	  ping_qmgr $i	# ping the QMs
	#echo $i
done

                      
