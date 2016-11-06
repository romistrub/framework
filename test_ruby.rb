

=begin

puts "s" + Random.new_seed.to_s

=begin
def add_user (name:, password:)
	p name, password
end

method(:add_user).call({name:"zorgon", password:"power_rangers"})

=begin

class C
	RPC = {"x" => "y"}
	def x
		puts 'in x'
	end
	def y
		puts 'in y'
	end
end
obj = C.new
obj.send(C::RPC["x"])

=begin

class C
	def initialize
		@a = 1
		@b = "z"
		@a = @b
		@b = "a"
		puts @a
	end
end

C.new

=begin

def f(x:1,y:2,z:)
	puts z
end

f(z:3)


=begin

class Class
	attr_reader :options
	
	DEFAULT_OPTIONS = {b: 2, c: 3}
	def initialize(a = 1, options={})
		@options = DEFAULT_OPTIONS.merge(options)
	end
end

obj = Class.new(0, {c:33, d:24})
puts obj.options

=begin
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
