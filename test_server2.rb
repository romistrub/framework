require 'socket'

TCPServer.new('',80)
loop {
	socket = TCPServer.accept
	s = socket.recv(1024)
	puts s.length
}