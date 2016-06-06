#!/usr/bin/env ruby

require 'socket'

socket = TCPSocket.new('localhost',81)

outHeaders="GET / HTTP/1.1\r\n"
outHeaders<<"Upgrade: websocket\r\n"
outHeaders<<"Connection: Upgrade\r\n"
outHeaders<<"Host: localhost:81\r\n"
outHeaders<<"Origin: http://localhost\r\n"
outHeaders<<"Pragma: no-cache\r\n"
outHeaders<<"Sec-WebSocket-Key: RmOFPqK2f2X4599xgxjonA==\r\n"
outHeaders<<"Sec-WebSocket-Version: 13"

socket.send(outHeaders, 0)
