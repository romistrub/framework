# observe time it takes between connection accepted and data received

require "socket"

t = TCPServer.new('',3000)
loop {
	Thread.start(t.accept) {|socket|
		puts "connection accepted"
		s = socket.recv(1024)
		puts "received #{s} length: #{s.length}"
		socket.close
	}
}

=begin

require 'socket'

def log(s)
  puts "#{Time.now.strftime('%H:%M:%S')}: #{s}"
end

html = "<a href=\"/foo\">Link</a>"

server = TCPServer.new('', 1337)

loop do
  socket = server.accept
  log "New connection, new socket"
  s = socket.recv(1024)
  log "#{s.bytesize}b: #{s.split("\r\n")[0]}"
	puts 'ok'
  if socket.eof?
	puts 'a'
    log "Socket closed by browser"
  else
	puts 'b'
    log "Sending response"
    socket.puts "HTTP/1.1 200 OK"
    socket.puts "Content-Length: #{html.bytesize}"
    socket.puts
    socket.write html
    socket.close
  end
  puts
end
=end