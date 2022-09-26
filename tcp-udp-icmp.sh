#!/usr/bin/bash

###Vars###

numOfPackets=1024 #total number of packets to send
portNum=1337 #TCP&UDP port number
hostIPAdrr=127.0.0.1 #server IP address
#pktLoss=1 #controls how many packets will be dropped during execution
outputFileName=pkt-capture.pcap

###Functions###

checkSuperUserAcess () {
if [ "$EUID" -ne 0 ]
    then echo "Please run this script as root!"
    exit 1
fi
}

printMessageDone () {
echo "[ OK ]"
}

#controls how many packets will be dropped during execution
configurePacketLoss () {
if [ $# -eq 1 ]
    then pktLoss=$1 
        echo -e "[INFO] Packet loss set to $1%\n"
    else pktLoss=0
        echo -e "[INFO] Packet loss NOT set\n"
fi
}

#sends 32 bytes of random data
sendData () {
for (( n = 0; n < $numOfPackets; n++ ));
do
    head --bytes 32 /dev/random >&3
done
}

closeClientProcess () {
exec 3>&-
exec 3<&-
}

execTCP () {
echo -n "[EXEC] Sending TCP packets ... "
exec 3<>/dev/tcp/$hostIPAdrr/$portNum
if [ $? -ne 0 ]; then serverStop; exit 1; fi
printMessageDone
}

execUDP () {
echo -n "[EXEC] Sending UDP packets ... "
exec 3<>/dev/udp/$hostIPAdrr/$portNum
if [ $? -ne 0 ]; then serverStop; exit 1; fi
printMessageDone
}

execICMP () {
echo -n "[EXEC] Sending ICMP packets ... "
ping -i 0.002 -c $numOfPackets -q $hostIPAdrr > /dev/null 2>&1
if [ $? -ne 0 ]; then serverStop; exit 1; fi
printMessageDone
}

serverStart () {
echo -n "[EXEC] Starting the TCP & UDP server sockets ... "

socat tcp-listen:$portNum,reuseaddr,fork open:/dev/null,creat,append &

socat udp-listen:$portNum,reuseaddr,fork open:/dev/null,creat,append &

sleep 2 #waits the server to finish opening

printMessageDone
}

serverAndSniferStop () {
echo -n "[EXEC] Stopping the server sockets ... "
pkill -15 socat >/dev/null 2>&1
printMessageDone
echo -n "[EXEC] Stopping the packet capture ... "
sleep 2 #waits the tcpdump buffer to finish writing the output file
pkill -2 tcpdump >/dev/null 2>&1
printMessageDone
echo -e "[INFO] Capture file saved as $outputFileName \n"
}

snifferStart () {
echo -n "[EXEC] Starting the packet capture ... "
tcpdump -U -w $outputFileName -i lo port $portNum or icmp > /dev/null 2>&1 &
printMessageDone
}

enablePktLoss () {
if [ "$pktLoss" -eq 0 ]
    then echo "[INFO] Running without packet drop!"
    else
        echo -n "[EXEC] Configuring kernel to $pktLoss% packet loss ... "
        tc qdisc add dev lo root netem loss $pktLoss%
        printMessageDone
fi
}

#needed to undo the modifications made by enablePktLoss function
disablePktLoss () {
if [ "$pktLoss" -ne 0 ]
    then
        echo -n "[EXEC] Reverting the $pktLoss% packet loss ... "
        tc qdisc del dev lo root
        printMessageDone
fi
}

###Script execution###

#Verify if user has root privileges before running anything
checkSuperUserAcess
echo -e "--- Begin of execution sockets test script ---\n"
#Start the packet drop (depends on pktLoss var)
configurePacketLoss $@
enablePktLoss
#Start monitor
snifferStart
#Start server
serverStart
#Client functionality
echo -e "[INFO] Starting the client process\n"
#TCP traffic
execTCP
sendData
closeClientProcess
#UDP traffic
execUDP
sendData
closeClientProcess
#ICMP traffic
execICMP
echo -e "[INFO] The client process is done\n"
#Stop the packet drop
disablePktLoss
#Close background processes
serverAndSniferStop
echo -e "[INFO] The server process is done\n"
echo "--- End of execution of sockets test script ---"
