#!/bin/bash
## Author(s): warybyte
## ==========================================================================================
##
## Sends alert for 'GF-Files are stopped' to Alerts Channel Microsoft Teams Workflow
##
## Last Edit: 04/09/2026
##
## Change Log:
## 04/09/2026 - add URL accessibility test / redirect alerts to Prod Alerts channel - jmcdill
## 04/14/2026 - add logic to automatically increase/decrease GF-Files retention time - jmcdill
## ==========================================================================================

###
### DEFINE GLOBAL VARS
###
LOGLOCATION="/var/log/GF-Files-healthcheck.log";
STATEFILE="/opt/file-check/statefile";

###
### DEFINE FUNCTIONS (MAIN AT BOTTOM OF FILE)
###
GF-Filescheck_alert_func(){
        ##
        ## Alert channel setup and templating
        ##
        ## TEST CHANNEL
        TEAMSCHANNEL="https://<YOURCHANNEL>"
        
        ## Since MS Workflows requires JSON formatted payloads, I'm building the template into the script, which is
        ## modified with specific alert data before transmission. This removes the need to have JSON config files
        ## laying around for each alert.

        PAYLOAD_PRIMER=$(
        cat <<EOF
        {
            "type": "message",
            "attachments": [
                {
                    "contentType": "application/vnd.microsoft.card.adaptive",
                    "contentUrl": null,
                    "content": {
                        "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
                        "type": "AdaptiveCard",
                        "version": "1.2",
                        "body": [
                            {
                                "type": "TextBlock",
                                "text": "GARAGEFS-ALERT",
                                "wrap": "True"
                            },
                                                {
                                "type": "TextBlock",
                                "text": "Critical Alert: ERRORCODE",
                                "wrap": "True"
                            },
                            {
                                "type": "TextBlock",
                                "text": "https://garagefs-url.local/home",
                                "wrap": "True"
                            }
                        ]
                    }
                }
            ]
        }
EOF
)
        ##
        ## High-level check of over-all disc usage
        ##

        ##
        ## DEFINE ERROR CODES
        ##

        # Professional
        ERROR0="GF-Files storage is over 95%. This is a warning.";
        ERROR1="GF-Files storage is over 97%. Action required to purge old GF-Files";
        ERROR2="GF-Files no longer generating. Restarting Docker container to clear stuck processes";
        ERROR3="Docker restart failed to resolve. Action required to diagnose issue";
        ERROR4="GF-Files are writing again. No further action required";
        ERROR5="GF-Files healthy. No action required";
        ERROR6="GF-Files URL appears to be broken. Restarting";
        ERROR7="Pruning old GF-Files";

        ##
        ## COLLECT STATE VALUES
        ##

        GF-Files_CAP=$(df -h /mnt/GF-Files | tail -1 | awk -F ' ' '{print $5}' | sed s/%//g);
        COUNT_ONE=$(df /mnt/GF-Files | awk -F ' ' '{print $3}' | tail -1);

        # 30 second sleep to distinguish count values
        sleep 30;

        COUNT_TWO=$(df /mnt/GF-Files | awk -F ' ' '{print $3}' | tail -1);
        echo "$(date +%Y%m%d":"%H%M) - Disk counts are $COUNT_ONE and $COUNT_TWO" >> $LOGLOCATION

        ##
        ## Test state and alert as needed
        ##

        if [ $GF-Files_CAP -gt 95 ];
        then
                echo "$(date +%Y%m%d":"%H%M) - GF-Files storage ERROR - $GF-Files_CAP%" >> $LOGLOCATION;

                # alert channel...jq for parsing json template, sed to replace text with appropriate error message

                PAYLOAD=$(echo $PAYLOAD_PRIMER | jq '.' | sed "s|ERRORCODE|$ERROR0|g");
                curl -X POST $TEAMSCHANNEL -H "Content-Type: application/json" -d "$PAYLOAD"
                echo 'unhealthy' > /opt/file-check/statefile

                # function to automatically reduce GF-Files retention
                sed -i s/MMIN=5760/MMIN=5060/g /opt/file-check/purge_scripts/reset-purge.sh
                /bin/bash /opt/file-check/purge_scripts/reset-purge.sh
        else
                echo "$(date +%Y%m%d":"%H%M) - GF-Files storage OK - $GF-Files_CAP%" >> $LOGLOCATION;
                echo 'healthy' > /opt/file-check/statefile

                # function to automatically increase GF-Files retention
                sed -i s/MMIN=5060/MMIN=5760/g /opt/file-check/purge_scripts/reset-purge.sh
                /bin/bash /opt/file-check/purge_scripts/reset-purge.sh

                # poll disk writes

                if [ $COUNT_ONE -eq $COUNT_TWO ];
                then
                        # fire alert...these shouldn't be the same

                        PAYLOAD=$(echo $PAYLOAD_PRIMER | jq '.' | sed "s|ERRORCODE|$ERROR2|g");
                        curl -X POST $TEAMSCHANNEL -H "Content-Type: application/json" -d "$PAYLOAD"
                        echo "$(date +%Y%m%d":"%H%M) - $ERROR2" >> $LOGLOCATION;
                        echo 'unhealthy' > /opt/file-check/statefile

                        # restart docker

                        /usr/bin/docker restart GF-Files-garage-s3-1
                        sleep 60

                        # recheck writes

                        COUNT_ONE=$(df /mnt/GF-Files | awk -F ' ' '{print $3}' | tail -1);
                        sleep 30;
                        COUNT_TWO=$(df /mnt/GF-Files | awk -F ' ' '{print $3}' | tail -1);

                        if [ $COUNT_ONE -eq $COUNT_TWO ];
                        then
                                PAYLOAD=$(echo $PAYLOAD_PRIMER | jq '.' | sed "s|ERRORCODE|$ERROR3|g");
                                curl -X POST $TEAMSCHANNEL -H "Content-Type: application/json" -d "$PAYLOAD";
                                echo "$(date +%Y%m%d":"%H%M) - $ERROR3" >> $LOGLOCATION;
                                echo 'unhealthy' > /opt/file-check/statefile
                        else
                                PAYLOAD=$(echo $PAYLOAD_PRIMER | jq '.' | sed "s|ERRORCODE|$ERROR4|g");
                                curl -X POST $TEAMSCHANNEL -H "Content-Type: application/json" -d "$PAYLOAD";
                                echo "$(date +%Y%m%d":"%H%M) - $ERROR4" >> $LOGLOCATION;
                                echo 'healthy' > /opt/file-check/statefile
                                                        fi
                else
                        PAYLOAD=$(echo $PAYLOAD_PRIMER | jq '.' | sed "s|ERRORCODE|$ERROR5|g");
                        echo "$(date +%Y%m%d":"%H%M) - $ERROR5" >> $LOGLOCATION;
                        echo 'healthy' > /opt/file-check/statefile
                fi
        fi
# close function GF-Filescheck_alert_func()
}

GF-Filescheck_noalert_func(){

        ##
        ## High-level check of over-all disc usage
        ##

        ##
        ## DEFINE ERROR CODES
        ##

        # Professional
        ERROR0="GF-Files storage is over 95%. This is a warning.";
        ERROR1="GF-Files storage is over 97%. Action required to purge old GF-Files";
        ERROR2="GF-Files no longer generating. Restarting Docker container to clear stuck processes";
        ERROR3="Docker restart failed to resolve. Action required to diagnose issue";
        ERROR4="GF-Files are writing again. No further action required";
        ERROR5="GF-Files healthy. No action required";
        ERROR6="GF-Files URL appears to be broken. Restarting";

        ##
        ## COLLECT STATE VALUES
        ##

        GF-Files_CAP=$(df -h /mnt/GF-Files | tail -1 | awk -F ' ' '{print $5}' | sed s/%//g);
        COUNT_ONE=$(df /mnt/GF-Files | awk -F ' ' '{print $3}' | tail -1);

        # 30 second sleep to distinguish count values
        sleep 30;

        COUNT_TWO=$(df /mnt/GF-Files | awk -F ' ' '{print $3}' | tail -1);

        ##
        ## Test state and alert as needed
        ##

        if [ $GF-Files_CAP -gt 95 ];
        then
                 echo "$(date +%Y%m%d":"%H%M) - GF-Files storage ERROR - $GF-Files_CAP%" >> $LOGLOCATION;

                # alert channel...jq for parsing json template, sed to replace text with appropriate error message

                echo 'unhealthy' > /opt/file-check/statefile

                # function to automatically reduce GF-Files retention
                sed -i s/MMIN=5760/MMIN=5060/g /opt/file-check/purge_scripts/reset-purge.sh
                /bin/bash /opt/file-check/purge_scripts/reset-purge.sh
        else
                echo "$(date +%Y%m%d":"%H%M) - GF-Files storage OK - $GF-Files_CAP%" >> $LOGLOCATION;
                echo 'healthy' > /opt/file-check/statefile

                # function to automatically increase GF-Files retention
                sed -i s/MMIN=5060/MMIN=5760/g /opt/file-check/purge_scripts/reset-purge.sh
                /opt/file-check/purge_scripts/reset-purge.sh

                # poll disk writes

                if [ $COUNT_ONE -eq $COUNT_TWO ];

                then
                        # fire alert...these shouldn't be the same

                        #PAYLOAD=$(echo $PAYLOAD_PRIMER | jq '.' | sed "s|ERRORCODE|$ERROR2|g");
                        echo "$(date +%Y%m%d":"%H%M) - $ERROR2" >> $LOGLOCATION;
                        echo 'unhealthy' > /opt/file-check/statefile

                        # restart docker

                        /usr/bin/docker restart GF-Files-garage-s3-1
                        sleep 60

                        # recheck writes

                        COUNT_ONE=$(df /mnt/GF-Files | awk -F ' ' '{print $3}' | tail -1);
                        sleep 30;
                        COUNT_TWO=$(df /mnt/GF-Files | awk -F ' ' '{print $3}' | tail -1);

                        if [ $COUNT_ONE -eq $COUNT_TWO ];
                        then
                                #PAYLOAD=$(echo $PAYLOAD_PRIMER | jq '.' | sed "s|ERRORCODE|$ERROR3|g");
                                echo "$(date +%Y%m%d":"%H%M) - $ERROR3" >> $LOGLOCATION;
                                echo 'unhealthy' > /opt/file-check/statefile
                        else
                                #PAYLOAD=$(echo $PAYLOAD_PRIMER | jq '.' | sed "s|ERRORCODE|$ERROR4|g");
                                echo "$(date +%Y%m%d":"%H%M) - $ERROR4" >> $LOGLOCATION;
                                echo 'healthy' > /opt/file-check/statefile
                        fi
                        return 1
                else
                        #PAYLOAD=$(echo $PAYLOAD_PRIMER | jq '.' | sed "s|ERRORCODE|$ERROR5|g");
                        echo "$(date +%Y%m%d":"%H%M) - $ERROR5" >> $LOGLOCATION;
                        echo 'healthy' > /opt/file-check/statefile
                        return 0
                fi
        fi
# close function GF-Filescheck_noalert_func()
}

GF-Filescheck_url_func(){
        curl http://garagefs-url.local:3900 &> /dev/null
        CURL_CHECK=$(echo $?)
        if [[ "$CURL_CHECK" == "0" ]]
        then
                echo 'healthy' > /opt/file-check/statefile;
        else
                PAYLOAD=$(echo $PAYLOAD_PRIMER | jq '.' | sed "s|ERRORCODE|$ERROR6|g");
                echo "$(date +%Y%m%d":"%H%M) - $ERROR6" >> $LOGLOCATION;
                curl -X POST $TEAMSCHANNEL -H "Content-Type: application/json" -d "$PAYLOAD";
                echo 'unhealthy' > /opt/file-check/statefile;
        fi
# close function GF-Filescheck_url_func()
}

##
## Should be integrated now with filesystem checks without needing more calls...
##
#GF-Filescheck_disk_func(){
#       # function to automatically dial back GF-Files retention
#       sed -i s/MMIN=5760/MMIN=5060/g /opt/file-check/purge_scripts/reset-purge.sh
#       /opt/file-check/purge_scripts/reset-purge.sh
#
#       # close GF-Filescheck_disk_func()
#}

###
### MAIN FUNCTION
###
# Statefile is used to prevent retriggering alerts to Teams. If last known state is healthy,
# system will proceed with alerts. If unhealthy, it will proceed without alerts...as the
# assumption is alerts have already fired.

STATEFILE=/opt/file-check/statefile

OVERALL_STATE=$(cat $STATEFILE)

# Check GF-Files disk
if [[ "$OVERALL_STATE" == "healthy" ]];
then
        # function with alerts (assumes healthy)
        echo "$(date +%Y%m%d":"%H%M) - Running healthy check" >> $LOGLOCATION;
        GF-Filescheck_alert_func
else
        # function without alerts (assumes already alerted)
        echo "$(date +%Y%m%d":"%H%M) - Running unhealthy check" >> $LOGLOCATION;
        GF-Filescheck_noalert_func
fi

# Check GF-Files main URL
GF-Filescheck_url_func