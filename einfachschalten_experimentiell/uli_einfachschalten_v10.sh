#!/bin/bash
# Testscript fur Optimierung Schaltschwellen
# kein Eingriff ins System shutdown etc
# große Testintervalle kleine Last?
# v6 maxpv 100 enn der SOC bei 90 ist es zwischen 13:00 und 13:59 uhr ist und die Module 4 Prozent auseinder sind mit pvstrom laden auf 100 %
# v7 Prozesse agetty killen, Alarme alle 10 Minuten, batterie alle 10 Minuten, bmm restart  
# v8 auch maxpv100 wenn Modul auf 9 springt
# v9 Ausgaben in log erweitert und korrket timestamp logfile
# v10 Beschreibung erweitert, Reset BMM, Ladefunktion per Variabel schaltbar

_DATUM_=$(date +"%Y-%m-%d_%H-%M")
_LOGFILE_=/home/admin/bin/uli_einfachschalten_${_DATUM_}.txt

echo "Script einfach in Konsole starten oder ueber crontab mit Pruefung ob es scho läeuft." | tee -a ${_LOGFILE_}
echo "ES wird der Duchschnitt der letzten 60 Sekundne gebildet, dieser Wert wird dann mit den in Variablen gesetzten Werten verglichen." | tee -a ${_LOGFILE_}
echo "Variable ab wann eingespeichert wird _SCHWELLEOBEN_" | tee -a ${_LOGFILE_}
echo "Variable ab wann ausgespeichert wird _SCHWELLEUNTEN_" | tee -a ${_LOGFILE_}
echo "Bei jedem Start wird ein logfile angelegt mit Start Datum/Uhrzeit." | tee -a ${_LOGFILE_}
echo "Wenn BO laeuft wird abgebrochen um Wechselwirkunken zu vermeiden." | tee -a ${_LOGFILE_}
echo "SOC Hysterese nach oben wenn einmal 90 erreicht wirde erst unter 87 wieder eingespeichert." | tee -a ${_LOGFILE_}
echo "Bei Sony-Anlagen wird wenn der SOC bei 90 ist es zwischen 13:00 und 13:59 uhr ist und die Module 4 Prozent auseinder sind mit pvstrom laden auf 100 %," | tee -a ${_LOGFILE_} 
echo "oder wenn Module auf 10 % springen. Diese automatische laden muss mit der Variable _AUTOLADEN_=ja im Script gesetzt werden!" | tee -a ${_LOGFILE_}
echo " " | tee -a ${_LOGFILE_}
echo "Wenn das testen beendet wird sollten diese 2 Befehle zur Sicherheit gesetzt werden." | tee -a ${_LOGFILE_}
echo "rm /home/admin/registry/noPVBuffering" | tee -a ${_LOGFILE_}
echo "echo \"0.90\" > /home/admin/registry/polMaxPV" | tee -a ${_LOGFILE_}

_SOCMAX_=90
_SOCHYSTERESE_=87
_SCHWELLEOBEN_=3000
_SCHWELLEUNTEN_=-1500
_AUTOLADEN_=nein
_SOCDCSPRUNG_=no
_BMMTYPE_=$(cat /home/admin/registry/out/bmmType)
printf -v _SOCMAX_ %.0f $_SOCMAX_
echo "SOC Maximalwert eingestellt ${_SOCMAX_}" | tee -a ${_LOGFILE_}
printf -v _SOCHYSTERESE_ %.0f $_SOCHYSTERESE_
echo "SOC Hysterese eingestellt ${_SOCHYSTERESE_}" | tee -a ${_LOGFILE_}
printf -v _SCHWELLEOBEN_ %.0f $_SCHWELLEOBEN_
echo "Leistungsgreneze einspeichern ${_SCHWELLEOBEN_}" | tee -a ${_LOGFILE_}
printf -v _SCHWELLEUNTEN_ %.0f $_SCHWELLEUNTEN_
echo "Leistungsgreneze ausspeichern ${_SCHWELLEUNTEN_}" | tee -a ${_LOGFILE_}
echo "Automatischen laden aktiviert: ${_AUTOLADEN_}" | tee -a ${_LOGFILE_}

# Einmalige Aktionen beim Start
# Killen agetty 
sudo pkill -SIGTERM agetty
# Abbrechen wenn BO laeuft unbekannte Wechselwirkungen
if [ ! $(ps aux | grep -c "[B]usinessOptimum.sh") = 0 ];
then
	echo "BusinessOptimum.sh laeuft auf dieser Anlage, das ist nicht erprobt es wird abgebrochen!!!" | tee -a ${_LOGFILE_}
	exit 0
fi

#Stoert beim testen, wird benoetigt??
#if [ -f /home/admin/registry/noPVBuffering ]
#then
#	rm /home/admin/registry/noPVBuffering
#	echo "rm /home/admin/registry/noPVBuffering" | tee -a ${_LOGFILE_}
#fi

if [ -f /home/admin/registry/polMaxPV ]
then
	echo "0.90" > /home/admin/registry/polMaxPV
fi


function fun_Daten_holen ()
{
# Holen letzten x Sekunden invoicelog, Durchschnitt hh, letzten soC    INFO Beachten Variabel 1 Zeile mehrer Zeilen
_DURCHSINVOIVE_=$(tail -60 /var/log/invoiceLog.csv | grep -v a)
_DURCHSHH_=$(echo "$_DURCHSINVOIVE_" | awk -F ";" 'BEGIN { lines=0; total=0 } { lines++; total+=$15 } END { print total/lines }')
printf -v _DURCHSHH_ %.0f $_DURCHSHH_
_DURCHSPV_=$(echo "$_DURCHSINVOIVE_" | awk -F ";" 'BEGIN { lines=0; total=0 } { lines++; total+=$14 } END { print total/lines }')
printf -v _DURCHSPV_ %.0f $_DURCHSPV_
_ENTLADENINV_=$(echo ${_DURCHSINVOIVE_} | awk -F ";" '{print $4147}')
_LADENINV_=$(echo ${_DURCHSINVOIVE_} | awk -F ";" '{print $4148}')
_SOCDC_=$(tail -n 2 /var/log/batteryLog.csv | grep -v '^#' | tail -n 1 | cut -d ";" -f6)
printf -v _SOCDC_ %.0f $_SOCDC_
if [ ${_SOCDC_} -le 10  ]
then
	_SOCDCSPRUNG_=yes
fi
_AKTTIME_=$(echo ${_DURCHSINVOIVE_} | awk -F ";" '{print $4132}')
_PV_=$(echo ${_DURCHSINVOIVE_} | awk -F ";" '{print $4144}')
let "_DURCHSPVHH_=_DURCHSPV_-_DURCHSHH_"
printf -v _DURCHSPVHH_ %.0f $_DURCHSPVHH_
_INVSTATUS_=$(tail -n1 /var/log/batteryLog.csv | cut -d ";" -f 25) 
}

function fun_setzten_einausspeichern ()
{
if [ ${_DURCHSPVHH_} -gt ${_SCHWELLEOBEN_} -o  ${_DURCHSPVHH_} -lt ${_SCHWELLEUNTEN_} ]
then
	echo "Normal Betrieb" | tee -a ${_LOGFILE_} 
	if [ -f /home/admin/registry/noPVBuffering ]
	then	
		rm /home/admin/registry/noPVBuffering
		echo "rm /home/admin/registry/noPVBuffering" | tee -a ${_LOGFILE_}
	fi 
else
	echo "ein/ausspeichern blockiert" | tee -a ${_LOGFILE_}
        if [ ! -f /home/admin/registry/noPVBuffering ]
        then
                touch /home/admin/registry/noPVBuffering
		echo "touch /home/admin/registry/noPVBuffering" | tee -a ${_LOGFILE_}
        fi
fi
} 

function fun_log_aktuell ()
{
if [ "${_AKTTIME_}" == "${_OLDAKTTIME_}" ]
then
        _STOP_="stop Invoicelog laeuft nicht!"
	echo "Logfile steht" | tee -a ${_LOGFILE_}
fi
_OLDAKTTIME_=$_AKTTIME_
}


function fun_Hysterese_Einspeichern ()
{
if [ ${_DURCHSPVHH_} -gt ${_SCHWELLEOBEN_} ]
then
	if [ ${_SOCDC_} -ge ${_SOCMAX_} ]
	then
		_SOCSTAT_=voll
		_STOP_="stop Einspeicher Hysterese"
	else 
		if [[ ${_SOCSTAT_} == "voll" ]]
		then 
			if [ ${_SOCDC_} -gt ${_SOCHYSTERESE_} ]
			then 		
				_STOP_="stop Einspeicher Hysterese"
			else
				_SOCSTAT_=normal
			fi
		fi	
	fi	
fi
}


function fun_maxPV_unterschied ()
{
if [ "$(echo ${_AKTTIME_} | cut -d " " -f2 | cut -d : -f1)" == "13" -a "${_BMMTYPE_}" == "sony" -a ${_SOCDC_} -ge 89 ] 
then 
	_SOCMODULEALL_=$((echo "mod";sleep 0.3;echo "exit";) | netcat localhost 1338 | grep soc | awk -F " " '{print $4 " " $5 " " $6 " " $7 " " $8 " " $9 " " $10 " " $11 " " $12 " " $13}')	
	_SOCMODULEMAX_=90
	for i in ${_SOCMODULEALL_}
	do 
		if [ ${i} -ge ${_SOCMODULEMAX_} ]
		then 
			_SOCMODULEMAX_=$i
			printf -v _SOCMODULEMAX_ %.0f $_SOCMODULEMAX_			
		fi 
	done
	if [ ${_SOCMODULEMAX_} -ge 940 ]
	then
	echo "Aufladen auf 100 Prozent gestartet da Module 4 differenz haben Dauer 3 Stunden" | tee -a ${_LOGFILE_}	 
	fun_laden
	fi
fi	
}

function fun_maxPV_sprung ()
{
if [ "$(echo ${_AKTTIME_} | cut -d " " -f2 | cut -d : -f1)" == "13" -a "${_BMMTYPE_}" == "sony" -a "${_SOCDCSPRUNG_}" == "yes" ] 
then 	
	echo "Aufladen auf 100 Prozent gestartet da Module auf 10 Prozent oder darunter waren." | tee -a ${_LOGFILE_}	 
	fun_laden
	_SOCDCSPRUNG_=no	
fi	
}

function fun_laden ()
{
if [ -f /home/admin/registry/noPVBuffering ]
then
	rm /home/admin/registry/noPVBuffering
	echo "rm /home/admin/registry/noPVBuffering" | tee -a ${_LOGFILE_}
fi
echo "1.00" > /home/admin/registry/polMaxPV
echo "1.00 > /home/admin/registry/polMaxPV" | tee -a ${_LOGFILE_}
_ZAEHLER_=1
while [ ${_ZAEHLER_} -le 120 ]
do
	fun_Daten_holen
	echo "${_AKTTIME_} Aktuell: PV vorhanden ${_PV_} Status Inv ${_INVSTATUS_}  SOCDC ${_SOCDC_} Laden WR ${_LADENINV_} ENTLADEN WR ${_ENTLADENINV_}" | tee -a ${_LOGFILE_}
	(echo "mod";sleep 0.3;echo "exit";) | netcat localhost 1338 | sed -n '18p;25,39p;' | tee -a ${_LOGFILE_}
	sleep 60s
	echo "PV-Ladung auf 100 Prozent laeuft seit ${_ZAEHLER_} Minuten von max 120" | tee -a ${_LOGFILE_}
	((_ZAEHLER_++))
	if [ ${_SOCDC_} -ge 100 ]
	then
		echo "0.90" > /home/admin/registry/polMaxPV
		echo "0.90 > /home/admin/registry/polMaxPV SOC 100" | tee -a ${_LOGFILE_}
	fi
done
echo "0.90" > /home/admin/registry/polMaxPV
echo "0.90 > /home/admin/registry/polMaxPV 2 Stunden abgelaufen" | tee -a ${_LOGFILE_}
(echo "mod";sleep 0.3;echo "exit";) | netcat localhost 1338 | sed -n '18p;25,39p;' | tee -a ${_LOGFILE_}
echo "1 Stunde Akkus ruhen lassen" | tee -a ${_LOGFILE_}
sleep 3600	
(echo "mod";sleep 0.3;echo "exit";) | netcat localhost 1338 | sed -n '18p;25,39p;' | tee -a ${_LOGFILE_}
echo "Restart bmm, dann 5 Minute Pause, SoC vergleichen gibt es eine Veränderung! " | tee -a ${_LOGFILE_}
source /home/admin/bin/modules/bc/resetBMM
swarmBcResetBmm 2 &> /dev/null   <<< j
sleep 30
(echo "mod";sleep 0.3;echo "exit";) | netcat localhost 1338 | sed -n '18p;25,39p;' | tee -a ${_LOGFILE_}
sleep 30
(echo "mod";sleep 0.3;echo "exit";) | netcat localhost 1338 | sed -n '18p;25,39p;' | tee -a ${_LOGFILE_}
sleep 30
(echo "mod";sleep 0.3;echo "exit";) | netcat localhost 1338 | sed -n '18p;25,39p;' | tee -a ${_LOGFILE_}
sleep 30
(echo "mod";sleep 0.3;echo "exit";) | netcat localhost 1338 | sed -n '18p;25,39p;' | tee -a ${_LOGFILE_}
sleep 30
(echo "mod";sleep 0.3;echo "exit";) | netcat localhost 1338 | sed -n '18p;25,39p;' | tee -a ${_LOGFILE_}
sleep 30
(echo "mod";sleep 0.3;echo "exit";) | netcat localhost 1338 | sed -n '18p;25,39p;' | tee -a ${_LOGFILE_}
sleep 30
(echo "mod";sleep 0.3;echo "exit";) | netcat localhost 1338 | sed -n '18p;25,39p;' | tee -a ${_LOGFILE_}
sleep 30
(echo "mod";sleep 0.3;echo "exit";) | netcat localhost 1338 | sed -n '18p;25,39p;' | tee -a ${_LOGFILE_}
sleep 30
(echo "mod";sleep 0.3;echo "exit";) | netcat localhost 1338 | sed -n '18p;25,39p;' | tee -a ${_LOGFILE_}
sleep 30
(echo "mod";sleep 0.3;echo "exit";) | netcat localhost 1338 | sed -n '18p;25,39p;' | tee -a ${_LOGFILE_}
echo "Wieder Normalbetrieb" | tee -a ${_LOGFILE_}
}

function fun_10Minuten_Abfragen ()
{
if [ "$(echo ${_AKTTIME_} | cut -d " " -f2 | cut -d : -f2 | cut -c2)" == "0" -a "${_BMMTYPE_}" == "sony" ]
then
	echo "Ausgabe Batteriemodule alle 10 Minuten!"
	(echo "mod";sleep 0.3;echo "exit";) | netcat localhost 1338 | sed -n '18p;25,39p;' | tee -a ${_LOGFILE_}
	echo "Ausgabe Alarmemodule alle 10 Minuten!"
	cat /tmp/alarm_messages | tee -a ${_LOGFILE_}
fi	
}

#MAIN
while true
do
fun_Daten_holen
fun_log_aktuell
echo "${_AKTTIME_} Durchschnitt: hh ${_DURCHSHH_} PV ${_DURCHSPV_} PVHH ${_DURCHSPVHH_} Aktuell: Status Inv ${_INVSTATUS_}  SOCDC ${_SOCDC_} Laden WR ${_LADENINV_} ENTLADEN WR ${_ENTLADENINV_}" | tee -a ${_LOGFILE_} 
fun_Hysterese_Einspeichern
if [[ "${_STOP_}" == "stop"* ]]
then 
	echo ${_STOP_} | tee -a ${_LOGFILE_}
        if [ ! -f /home/admin/registry/noPVBuffering ]
        then
                touch /home/admin/registry/noPVBuffering
		echo "touch /home/admin/registry/noPVBuffering" | tee -a ${_LOGFILE_}
        fi
else
	fun_setzten_einausspeichern
fi
if [[ "${_AUTOLADEN_}" == "ja" ]]
then
	fun_maxPV_unterschied
	fun_maxPV_sprung
fi
_STOP_="leer"
fun_10Minuten_Abfragen
sleep 58.6
done

