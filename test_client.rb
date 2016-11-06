# test client 
require 'socket'
socket = TCPSocket.new("localhost", 3000)
#socket.write('')
sleep(5)
puts 'test'
#socket.write('test')
#socket.close

# assert goes here
socket.close
loop{}