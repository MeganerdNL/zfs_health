#! /bin/sh
#
# Calomel.org
#     https://calomel.org/zfs_health_check_script.html
#     FreeBSD ZFS Health Check script
#     zfs_health.sh @ Version 0.18.2

# Check health of ZFS volumes and drives. On any faults send email.

### DISCLAIMER AND CHANGES
#     Original version 0.18 - April 10 2020 https://calomel.org/zfs_health_check_script.html
#     I do not claim to be the original author of this script: credits to calomel.org
# Changelog (MeganerdNL):
#     - Added some lines to make the date logic work in Debian 10+ (based) systems
#     - A typo in a description
#     - Added rudimentary logging to a file support
###

# Set this to 1 to log to a file and 0 to disable logging to a file (email is always sent when there is an error)
logtofile=1
# Location of logfile if logtofile is set
logfile=/var/log/zfs_health.log

# 99 problems but ZFS aint one
problems=0

# Health - Check if all zfs volumes are in good condition. We are looking for
# any keyword signifying a degraded or broken array.

condition=$(/sbin/zpool status | egrep -i '(DEGRADED|FAULTED|OFFLINE|UNAVAIL|REMOVED|FAIL|DESTROYED|corrupt|cannot|unrecover)')
if [ "${condition}" ]; then
        emailSubject="`hostname` - ZFS pool - HEALTH fault"
        problems=1
fi

# Capacity - Make sure the pool capacity is below 80% for best performance. The
# percentage really depends on how large your volume is. If you have a 128GB
# SSD then 80% is reasonable. If you have a 60TB raid-z2 array then you can
# probably set the warning closer to 95%.
#
# ZFS uses a copy-on-write scheme. The file system writes new data to
# sequential free blocks first and when the uberblock has been updated the new
# inode pointers become valid. This method is true only when the pool has
# enough free sequential blocks. If the pool is at capacity and space limited,
# ZFS will be have to randomly write blocks. This means ZFS can not create an
# optimal set of sequential writes and write performance is severely impacted.

maxCapacity=80

if [ ${problems} -eq 0 ]; then
   capacity=$(/sbin/zpool list -H -o capacity | cut -d'%' -f1)
   for line in ${capacity}
     do
       if [ $line -ge $maxCapacity ]; then
         emailSubject="`hostname` - ZFS pool - Capacity Exceeded"
         problems=1
       fi
     done
fi

# Errors - Check the columns for READ, WRITE and CKSUM (checksum) drive errors
# on all volumes and all drives using "zpool status". If any non-zero errors
# are reported an email will be sent out. You should then look to replace the
# faulty drive and run "zpool scrub" on the affected volume after resilvering.

if [ ${problems} -eq 0 ]; then
   errors=$(/sbin/zpool status | grep ONLINE | grep -v state | awk '{print $3 $4 $5}' | grep -v 000)
   if [ "${errors}" ]; then
        emailSubject="`hostname` - ZFS pool - Drive Errors"
        problems=1
   fi
fi

# Scrub Expired - Check if all volumes have been scrubbed in at least the last
# 8 days. The general guide is to scrub volumes on desktop quality drives once
# a week and volumes on enterprise class drives once a month. You can always
# use cron to schedule "zpool scrub" in off hours. We scrub our volumes every
# Sunday morning for example.
#
# Scrubbing traverses all the data in the pool once and verifies all blocks can
# be read. Scrubbing proceeds as fast as the devices allows, though the
# priority of any I/O remains below that of normal calls. This operation might
# negatively impact performance, but the file system will remain usable and
# responsive while scrubbing occurs. To initiate an explicit scrub, use the
# "zpool scrub" command.
#
# The scrubExpire variable is in seconds. So for 8 days we calculate 8 days
# times 24 hours times 3600 seconds to equal 691200 seconds.

#scrubExpire=691200

# 36 days is sensible for scrubbing once a month on a specific weekday
# (e.g. every second Sunday of the month)
scrubExpire=3110400

if [ ${problems} -eq 0 ]; then
   currentDate=$(date +%s)
   zfsVolumes=$(/sbin/zpool list -H -o name)

  for volume in ${zfsVolumes}
   do
    if [ $(/sbin/zpool status $volume | egrep -c "none requested") -ge 1 ]; then
        printf "ERROR: You need to run \"zpool scrub $volume\" before this script can monitor the scrub expiration time."
        break
    fi
    if [ $(/sbin/zpool status $volume | egrep -c "scrub in progress|resilver") -ge 1 ]; then
        break
    fi

    ### Debian (based) 10 with GNU supported date format
     scrubRawDate=$(/sbin/zpool status $volume | grep scrub | awk '{print $12" "$13" " $14" " $15" "$16}')
     scrubDate=$(date -d "$scrubRawDate" +%s)

    ### Ubuntu with GNU supported date format
    #scrubRawDate=$(/sbin/zpool status $volume | grep scrub | awk '{print $11" "$12" " $13" " $14" "$15}')
    #scrubDate=$(date -d "$scrubRawDate" +%s)

    ### FreeBSD 11.2 with *nix supported date format
    #scrubRawDate=$(/sbin/zpool status $volume | grep scrub | awk '{print $15 $12 $13}')
    #scrubDate=$(date -j -f '%Y%b%e-%H%M%S' $scrubRawDate'-000000' +%s)

    ### FreeBSD 12.0 with *nix supported date format
    #scrubRawDate=$(/sbin/zpool status $volume | grep scrub | awk '{print $17 $14 $15}')
    #scrubDate=$(date -j -f '%Y%b%e-%H%M%S' $scrubRawDate'-000000' +%s)

     if [ $(($currentDate - $scrubDate)) -ge $scrubExpire ]; then
        emailSubject="`hostname` - ZFS pool - Scrub Time Expired. Scrub Needed on Volume(s)"
        problems=1
     fi
   done
fi

# Email - On any problems send email with drive status information and
# capacities including a helpful subject line. Also use logger to write the
# email subject to the local logs. This is also the place you may want to put
# any other notifications like playing a sound file, beeping the internal
# speaker, paging someone or updating Nagios or even BigBrother.

if [ "$problems" -ne 0 ]; then
  printf '%s\n' "$emailSubject" "" "`/sbin/zpool list`" "" "`/sbin/zpool status`" | /usr/bin/mail -s "$emailSubject" root@localhost
  logger $emailSubject
  if [ $logtofile = 1 ]; then
        echo $(/bin/date) zfs_health.sh error $emailSubject >> $logfile
  fi
fi

if [ $logtofile = 1 ]; then
    echo $(/bin/date) zfs_health.sh executed succesfully >> $logfile
fi

### EOF ###
