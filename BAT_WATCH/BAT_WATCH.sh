#!/bin/bash 
#v1 Ersterstellung Script um Sonyakkus zu beobachten 

_DATUM_=$(date +"%Y-%m-%d_%H-%M")
_LOGFILE_=/var/log/BAT_WATCH_${_DATUM_}.txt

while true
do
	if ! [ -f /home/admin/registry/out/gen2 ]; then
		echo "Device is not a gen2!" | tee -a ${_LOGFILE_}
	else

		(echo "mod";sleep 0.3;echo "exit";) | netcat localhost 1338 | sed -n '18p;25,39p;' | tee -a ${_LOGFILE_}
		for i in {30244..30259} {30369..30384} {30494..30509} {30619..30634} {30744..30759} {30869..30884} {30994..31009} {31119..31134} {31244..31259} {31369..31384}
		do (echo "reg ${i}"; sleep 0.3; echo "exit") | netcat localhost 1338; 
 		done | grep ^3 | tee -a ${_LOGFILE_}	
	fi
	sleep 240
	
done

