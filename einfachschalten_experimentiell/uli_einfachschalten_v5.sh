#!/bin/bash
# Testscript fur Optimierung Schaltschwellen
# kein Eingriff ins System shutdown etc
# große Testintervalle kleine Last?

# Momentan wird der duchschnitt der letzten 60 Sekundne gebildet.
# Bei ueber 2000 Watt ueberschuss wird eingespeichert.
# Bei mehr als -1500 Watt wird ausgespeichert.
# Schwellen stehen auch am Anfang im Logfile.
# Wenn jemand das testet bitte BO ausschalten.

_DATUM_=$(date +"%Y-%m-%d_%H-%M")
_LOGFILE_=/home/admin/bin/uli_einfachschalten_${_DATUM_}.txt

_SOCMAX_=90
_SOCHYSTERESE_=87
_SCHWELLEOBEN_=2000
_SCHWELLEUNTEN_=-1500
printf -v _SOCMAX_ %.0f $_SOCMAX_
echo "SOC Maximalwert eingestellt ${_SOCMAX_}" | tee -a ${_LOGFILE_}
printf -v _SOCHYSTERESE_ %.0f $_SOCHYSTERESE_
echo "SOC Hysterese eingestellt ${_SOCHYSTERESE_}" | tee -a ${_LOGFILE_}
printf -v _SCHWELLEOBEN_ %.0f $_SCHWELLEOBEN_
echo "Leistungsgreneze einspeichern ${_SCHWELLEOBEN_}" | tee -a ${_LOGFILE_}
printf -v _SCHWELLEUNTEN_ %.0f $_SCHWELLEUNTEN_
echo "Leistungsgreneze ausspeichern ${_SCHWELLEUNTEN_}" | tee -a ${_LOGFILE_}
if [ -f /home/admin/registry/noPVBuffering ]
then
	rm /home/admin/registry/noPVBuffering
fi

function fun_Daten_holen ()
{
# Holen letzten x Sekunden invoicelog, Durchschnitt hh, letzten soC    INFO Beachten Variabel 1 Zeile mehrer Zeilen
_DURCHSINVOIVE_=$(tail -60 /var/log/invoiceLog.csv | grep -v a)
_DURCHSHH_=$(echo "$_DURCHSINVOIVE_" | awk -F ";" 'BEGIN { lines=0; total=0 } { lines++; total+=$15 } END { print total/lines }')
printf -v _DURCHSHH_ %.0f $_DURCHSHH_
_DURCHSPV_=$(echo "$_DURCHSINVOIVE_" | awk -F ";" 'BEGIN { lines=0; total=0 } { lines++; total+=$14 } END { print total/lines }')
printf -v _DURCHSPV_ %.0f $_DURCHSPV_
_ENTLADENINV_=$(echo ${_DURCHSINVOIVE_} | awk -F ";" '{print $647}')
_LADENINV_=$(echo ${_DURCHSINVOIVE_} | awk -F ";" '{print $648}')
_SOCDC_=$(tail -n 2 /var/log/batteryLog.csv | grep -v '^#' | tail -n 1 | cut -d ";" -f6)
printf -v _SOCDC_ %.0f $_SOCDC_
_AKTTIME_=$(echo ${_DURCHSINVOIVE_} | awk -F ";" '{print $632}')
let "_DURCHSPVHH_=_DURCHSPV_-_DURCHSHH_"
printf -v _DURCHSPVHH_ %.0f $_DURCHSPVHH_
}

function fun_setzten_einausspeichern ()
{
if [ ${_DURCHSPVHH_} -gt ${_SCHWELLEOBEN_} -o  ${_DURCHSPVHH_} -lt ${_SCHWELLEUNTEN_} ]
then
	echo "Normal Betrieb" | tee -a ${_LOGFILE_} 
	if [ -f /home/admin/registry/noPVBuffering ]
	then	
		rm /home/admin/registry/noPVBuffering
	fi 
else
	echo "ein/ausspeichern blockiert" | tee -a ${_LOGFILE_}
        if [ ! -f /home/admin/registry/noPVBuffering ]
        then
                touch /home/admin/registry/noPVBuffering
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
	


#MAIN
while true
do
fun_Daten_holen
echo "${_AKTTIME_} Durchsnitt: hh ${_DURCHSHH_} PV ${_DURCHSPV_} PVHH ${_DURCHSPVHH_} Aktuell:  SOCDC ${_SOCDC_} Laden WR ${_LADENINV_} ENTLADEN WR ${_ENTLADENINV_}" | tee -a ${_LOGFILE_} 
fun_log_aktuell
fun_Hysterese_Einspeichern
if [[ "${_STOP_}" == "stop"* ]]
then 
	echo ${_STOP_} | tee -a ${_LOGFILE_}
        if [ ! -f /home/admin/registry/noPVBuffering ]
        then
                touch /home/admin/registry/noPVBuffering
        fi
else
	fun_setzten_einausspeichern
fi
_STOP_="leer"
sleep 59.5
done

