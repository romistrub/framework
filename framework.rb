#!/usr/bin/env ruby

# Author: Romi Strub
# Last Edited: 03-06-2016 (DD-MM-YYYY)

# WebSocket chat script.

# 


puts "RUBY_VERSION #{RUBY_VERSION}"
puts "Process.pid #{Process.pid}"

Thread.abort_on_exception = true

require 'digest/sha1'
require 'socket'
require 'awesome_print'


class Framework

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

	def self.byte_string_to_int(byte_string)

		bytes = byte_string.bytes
		bytes = bytes.reverse

		sum = 0

		bytes.each_index{|i|
			sum = sum + (bytes[i] << (8*i))
		}

		sum

	end

	module WebSocket

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
	
		class Server

			attr_reader :tcp_server, :hostname, :port
			attr_reader :connection_count, :connections, :connection_history

			def initialize (hostname, port)

				@tcp_server = TCPServer.new(hostname, port)
				@hostname = hostname
				@port = port

				@connection_count = 0
				@connections = []
				@connection_history = []
		
				puts "server started on port #{@port}" ##

				puts "\r\nSTART TESTS"
				#puts MyWebSocket.bytes_to_int([0,0,1])
				puts "END TESTS\r\n"
		
			end

			def accept(handlers)
	
				connection = Framework::WebSocket::Connection.new(@tcp_server.accept, self, handlers)

				@connection_count += 1
				@connections << connection
		
				puts "connection #{@connection_count} on port #{@port}" ##
				puts "local address: " + connection.socket.local_address.inspect
				puts "remote address: " + connection.socket.remote_address.inspect
				puts "connections:" ##
				ap @connections ##
		
				connection

			end

			def remove_connection(connection)

				@connection_count -= 1
				@connection_history << connection
				@connections.delete(connection)

			end

			def get_connection_number(connection)

				ap @connections
				@connections.find_index(connection) + 1

			end


		end

		class Connection

			attr_reader :socket, :server
			attr_reader :message_count, :messages

			def initialize(socket, server, handlers)

				@socket = socket
				@socket_open = true
				@server = server
				@message_count = 0
				@messages = []
				@on_open = handlers[:on_open] || proc {}
				@on_message = handlers[:on_message] || proc {}
				@on_close = handlers[:on_close] || proc {}

				handshake_response
		
				@on_open.call(self)

				# receive messages
				Thread.new {
		
					while @socket_open do
				
						frame = receive_frame
						opcode = frame["opcode"]
						payload = frame["payload"]
						fin = frame["fin"]
				
						puts "\r\n#########################################\r\n"

						puts "\r\nCONNECTION\r\n\r\n##{get_connection_number} #{@socket}"

						puts "\r\nDECODED FRAME\r\n\r\n"
						ap frame

						case opcode
						when 10 # pong
				
							# register pong successful
				
						when 9 # ping
				
							# send pong
							write encode_frame(true, 10, "")
				
						when 8 # close
				
							# mirror received close code
							close_code = Framework.byte_string_to_int(payload.slice!(0..1))

							close(close_code, payload)
				
						when 1..2 # text or binary
				
							message = add_message(payload)

							if fin
				
								messages << message
								@on_message.call(self, message)
				
							end
				
							puts "\r\nMESSAGE NUMBER\r\n\r\n#{@message_count}"

						when 0 # continuation
				
							message << payload
				
						end
				
					end
		
				}
			end
	
			def close(code, reason = "")
			# code expects integer
				@on_close.call(self)
				@socket.write encode_frame(true, 8, Framework.int_to_byte_string(code, 2) << reason) # encode close message
				@server.remove_connection(self)
				@socket.close
				@socket_open = false

				puts "\r\nCONNECTION CLOSED\r\n\r\n"
				puts "#{code}: #{reason}"
		
			end
	
			def add_message(msg)
	
				@message_count += 1
				Framework::WebSocket::Message.new(self, msg)
	
			end
	
			def handshake_response
	
				string = @socket.recv(1024)
		
				in_headers = Framework::parse_http_headers(string)
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

					@socket.write out_headers

					puts "RESPONSE SENT:" ##
					puts out_headers ##

				end
		
			end

			def receive_frame

				header = @socket.recv(2)

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
				byte_two = byte_two-128 if masked

				# get payload length
				if byte_two == 126
					payload_length = Framework.byte_string_to_int(@socket.recv(2))
				elsif byte_two == 127
					payload_length = Framework.byte_string_to_int(@socket.recv(8))
				else
					payload_length = byte_two
				end

				mask = @socket.recv(4) if masked

				# receieve payload
				payload = @socket.recv(payload_length)
	
				payload = Framework::WebSocket.unmask_payload(mask, payload) if masked
	
				frame = {
					"fin"=>final,
					"rsv1"=>reserve_1,
					"rsv2"=>reserve_2,
					"rsv3"=>reserve_3,
					"opcode"=>opcode,
					"masked"=>masked,
					"payload_length"=>payload_length,
					"mask"=>mask,
					"payload"=>payload
				}
			end

			def get_connection_number
				@server.get_connection_number(self)
			end

			def encode_frame(fin, opcode, payload)

				body = ""

				byte_one = (fin) ? 128 : 0
				byte_one += opcode

				if payload.length > 65535 # largest expressible integer using two bytes
					byte_two = 127
					body << Framework.int_to_byte_string(payload.length, 8)
				elsif payload.length > 125
					byte_two = 126
					body << Framework.int_to_byte_string(payload.length, 2)
				else
					byte_two = payload.length # assumes message is not masked
				end

				body << payload

				byte_one.chr << byte_two.chr << body

			end

			def write(content)
				@socket.write(content)
			end

		end

		class Message

			attr_reader :content, :connection

			def initialize(connection, msg = "")

				@content = msg
				@connection = connection
		
			end

			def <<(string)

				@content << string

			end

		end

	end

end

port = 9292

server = Framework::WebSocket::Server.new('', port)

# on_open, on_message, and/or on_close
handlers = {
	:on_message => proc {|connection, message|
		return_message = connection.encode_frame(true, 1, message.content)
		
		puts "\r\nCONNECTIONS\r\n\r\n"
		ap connection.server.connections
		
		connection.server.connections.each {|c|
			c.write return_message
		}
	}
}

loop {

	# receive connection
	server.accept handlers

}
