case 1
when 0, 1
puts "gotcha"
else
puts "missed ya"
end
=begin

class A
	module F
		C = 1
	end
	def initialize
		puts F::C
	end
end

A.new # returns 1

=begin
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

=end