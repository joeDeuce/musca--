#!/bin/bash

if [ "0$1" == "0" ]; then
	echo 'ewmh_window.sh cycle next|back'
	echo 'ewmh_window.sh switch'
	exit
fi
task=$1

desktops=`wmctrl -d`
desktopactive=`echo -ne "$desktops" | egrep '^[0-9]+[[:space:]]+\*' | awk '{print $1}'`;
windows=`wmctrl -l`
windowactive=$(printf "0x%08x" `xprop -root | egrep ^_NET_ACTIVE | awk '{print $5}'`);
windowslocal=`echo -ne "$windows" | egrep "^0x[0-9a-z]+[[:space:]]+$desktopactive"`

if [ $task == "cycle" ]; then
	windowids=`echo -ne "$windowslocal" | awk '{print $1}'`;
	possibles=`echo -e "$windowids\n$windowids\n$windowids" | grep $windowactive -A 1 -B 1 -m 2 | tail -n 3`;
	direction='next'
	if [ "0$2" == "0" ]; then
		direction=$2
	fi
	if [ $direction == 'next' ]; then
		wmctrl -i -a `echo "$possibles" | tail -n 1`;
	elif [$direction == 'back' ]; then
		wmctrl -i -a `echo "$possibles" | head -n 1`;
	fi

elif [ $task == 'switch' ]; then
	i=0
	IFS=$'\n'
	menu=''
	for window in `echo "$windowslocal"`; do
		match='-'
		if [ `expr match "$window" $windowactive` -ne 0 ]; then
			match='*'
		fi
		menu="$menu$i $match ${window:19}\n"
		((i++))
	done
	choice=`echo -en "$menu" | dmenu -b -i`
	if [ "0$choice" != "0" ]; then
		line=`expr "$choice" : '\([0-9]*\)'`
		wline=`echo -ne "$windowslocal" | head -n $((line+1)) | tail -n 1`
		wmctrl -i -a ${wline:0:10}
	fi

elif [ $task == 'desktop' ]; then
	if [ $2 == 'next' ]; then
		id=$((desktopactive+1))
	else
		id=$((desktopactive-1))
	fi
	count=$((`echo -e "$desktops" | wc -l`))
	if [ $id -lt 0 ]; then
		id=$((count-1))
	fi
	if [ $id -eq $count ]; then
		id=0
	fi
	wmctrl -s $id

fi
