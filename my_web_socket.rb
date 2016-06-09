#!/usr/bin/env ruby

# Author: Romi Strub
# Last Edited: 03-06-2016 (DD-MM-YYYY)

# WebSocket chat script.

# 



puts "RUBY_VERSION " + RUBY_VERSION
puts "Process.pid " + Process.pid.to_s


Thread.abort_on_exception = true

class MyWebSocketServer < TCPServer

	def initialize (hostname, port)

		server = super(hostname, port)
		@port = port
		@connection_count = 0
		@connections = []
		
		puts "server started on port #{@port}" ##

		puts "\r\nSTART TESTS"
		#puts MyWebSocket.bytes_to_int([0,0,1])
		puts "END TESTS\r\n"
		
	end
	def accept
	
		connection = MyWebSocket.new(self.accept, self)
		
		@connection_count += 1
		@connections << connection
		
		puts "connection #{@connection_count} on port #{@port}" ##
		puts "local address: " + connection.local_address.inspect
		puts "remote address: " + connection.remote_address.inspect
		puts "connections:" ##
		ap connections ##
		
		connection
	end
end

class MyWebSocket < TCPSocket

	def initialize(connection, server)
		@server = server
		@message_count = 0
		
		handshake
	end
	
	def handshake
	
		string = recv(1024)
		
		in_headers = MyWebSocket.parse_http_headers(string)
		ap in_headers ##

		if defined? in_headers["Sec-WebSocket-Key"]

			# compute response for WebSocket
			
			websocket_key = in_headers["Sec-WebSocket-Key"]
			key_suffix = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
			computed_key = Digest::SHA1.base64digest(websocket_key + key_suffix)

			out_headers =  "HTTP/1.1 101 Switching Protocols\r\n"
			out_headers << "Connection: Upgrade\r\n"
			out_headers << "Date: #{Time.now}\r\n"
			out_headers << "Sec-Websocket-Accept: #{computed_key}\r\n"
			out_headers << "Server: Ruby Websocket\r\n"
			out_headers << "Upgrade: websocket\r\n"
			out_headers << "\r\n"

			write out_headers

			puts "RESPONSE SENT:" ##
			puts out_headers ##

		end
		
	end

	def self.parse_http_headers(header_string)

		return_hash = {}

		lines = header_string.split("\r\n")
		first_line = lines.shift
		first_line_words = first_line.split(" ")
		
		return_hash["Method"] = first_line_words[0]
		return_hash["URI"] = first_line_words[1]
		return_hash["Protocol"] = first_line_words[2]
		
		lines.each {|line|
			key_val = line.split(": ")
			return_hash[key_val[0]] = key_val[1]
		}
		
		return_hash
		
	end

	def self.byte_string_to_int(byte_string)
	
		bytes = byte_string.bytes
		bytes = bytes.reverse
		ap bytes
		
		sum = 0
		
		bytes.each_index{|i|
			sum = sum + (bytes[i] << (8*i))
		}
		
		sum

	end
	
	def self.int_to_byte_string(int, string_length)
	
		# check to see if integer exceeds maximum size given by string_length

		max_int_size = (2**(8*string_length))-1
		
		if int > max_int_size
			raise ArgumentError, "integer #{int} exceeds maximum size allowed by string_length #{max_int_size}"
		end
		
		chars = []
		
		mask = 255 # 11111111 in binary
		
		while int > 0 do
			chars << (mask & int).chr
			int = int >> 8
		end 
		
		(string_length - chars.size).times{|c|
			chars << (0).chr
		}
		
		chars = chars.reverse
		chars.join
		
	end
	
	def self.unmask_payload(mask, payload)
		#mask expects string of 4 chars
		#payload expects string of n chars
		mask = mask.bytes
		payload = payload.bytes
		payload = payload.map.with_index{|byte, i|
			byte^mask[i%4] ## if either bit is 1, result is 1
		}
		payload.map{|c|c.chr}.join
	end
	
	def self.decode_frame(connection)
	
		header = connection.recv(2)
		
		bytes = header.bytes

		byte_one = bytes.shift

		# whittle down the first byte to get the opcode
		
		# first bit is set to one if message is final
		final = byte_one[7] == 1 ? true : false
		byte_one = final ? byte_one-128 : byte_one
		
		reserve_1 = byte_one[6]
		byte_one = reserve_1 == 1 ? byte_one-64 : byte_one
		
		reserve_2 = byte_one[5]
		byte_one = reserve_2 == 1 ? byte_one-32 : byte_one
		
		reserve_3 = byte_one[4]
		byte_one = reserve_3 == 1 ? byte_one-16 : byte_one
		
		opcode = byte_one

		byte_two = bytes.shift
		
		# first bit (of second byte) is set to one if message is masked
		masked = (byte_two[7] == 1) ? true : false
		
		# negate mask flag bit
		if masked
			byte_two = byte_two-128
		end
		
		# get payload length
		if byte_two == 126
			payload_length = self.byte_string_to_int(connection.recv(2))
		elsif byte_two == 127
			payload_length = self.byte_string_to_int(connection.recv(8))
		else
			payload_length = byte_two
		end
		
		if masked
			mask = connection.recv(4) # receieve mask string (4 bytes)
		end
		
		# receieve payload
		payload = connection.recv(payload_length)
				
		if masked
			payload = MyWebSocket.unmask_payload(mask, payload)
		end
				
		{"fin"=>final,
		"rsv1"=>reserve_1,
		"rsv2"=>reserve_2,
		"rsv3"=>reserve_3,
		"opcode"=> opcode,
		"masked"=> masked,
		"payload_length"=> payload_length,
		"mask"=>mask,
		"payload"=>payload}
	end
	
	def self.encode_frame(fin, opcode, payload)
	
		body = ""
	
		byte_one = (fin) ? 128 : 0
		byte_one += opcode
		
		if payload.length > 65535 # largest expressible integer using two bytes
			byte_two = 127
			body << MyWebSocket.int_to_byte_string(payload.length, 8)
		elsif payload.length > 125
			byte_two = 126
			body << MyWebSocket.int_to_byte_string(payload.length, 2)
		else
			byte_two = payload.length # assumes message is not masked
		end
		
		body << payload
		
		byte_one.chr << byte_two.chr << body
		
	end
end

require 'digest/sha1'
require 'socket'
require 'awesome_print' 


port = 9292

server = MyWebSocketServer.new('', port)

loop {

	connection = server.accept # returns MyWebSocket

	# begin receiving messages
	Thread.new {

		j = 0
		
		loop {
		
			j += 1

=begin
			k = 0
			frame = connection.recv(1024).bytes.each{|byte|
				k = k+1
				puts k.to_s + " " + byte.to_s(2)
			}
=end
#=begin			
			
			decoded_frame = MyWebSocket.decode_frame(this_connection)
			
			puts "\r\n#########################################\r\n"
			
			puts "\r\nCONNECTION\r\n\r\n ##{connections.find_index(connection)+1} #{connection}"
			
			puts "\r\nMESSAGE NUMBER\r\n\r\n#{j}"
			
			puts "\r\nDECODED FRAME\r\n\r\n"
			ap decoded_frame
						
			case decoded_frame["opcode"]
			when 8 # If opcode is 8, initiate close response
				
			when 1
			
				payload = decoded_frame["payload"]
				
				return_message = MyWebSocket.encode_frame(true, 1, payload)
				
				puts "\r\nCONNECTIONS\r\n\r\n"
				ap connections
				
				connections.each {|c|
					c.write return_message
				}	
				
			end
			
#=end
		}
	}

	##connection.close
}
