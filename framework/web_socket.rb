require_relative("../framework")
require_relative("../framework/http")
require 'digest/sha1'
require 'json'
require 'base64'

module Framework::WebSocket

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

end # Framework::WebSocket

class Framework::WebSocket::Server < Framework::HTTP::Server

	def socket_class
		Framework::WebSocket::Connection
	end

	def accept(*args)
		super(*args)
		puts "connections: #{@connections.length}" ##
	end

end # Framework::WebSocket::Server

class Framework::WebSocket::Connection < Framework::HTTP::Request

	attr_reader :message_count, :messages
	alias :super_close :close
	
	def initialize(socket:, server:, handlers:{})

		@handshake_successful = false
	
		http_handlers = {
			on_request: proc {
				handshake_response(@request_headers)
				@handshake_successful = true
			}
		}
	
		@on_open = handlers[:on_open] || proc {}
		@on_message = handlers[:on_message] || proc {}
		@on_close = handlers[:on_close] || proc {}
		
		super(socket:socket,server:server, handlers:http_handlers)

		@message_count = 0
		@messages = []

	end

	def response_complete

		if @handshake_successful
	
			@socket_open = true
			@on_open.call(self)

			# receive messages
			Thread.new {

				while @socket_open do

					handle_frame

				end

			}
			
		else
		
			super_close()
			
		end
	
	end
	
	def handshake_response(request_headers)

		# RFC 6455 4.2.1: Reading the Client's Opening Handshake
	
		raise Framework::HTTP::BadRequest.new("WebSocket RFC 6455 4.2.1.1 requires HTTP/1.1 or higher") unless request_headers["Protocol"] == "HTTP" && request_headers["ProtocolVersion"].to_f >= 1.1
		raise Framework::HTTP::BadRequest.new("WebSocket RFC 6455 4.2.1.1 requires GET method") unless request_headers["Method"] == "GET"

		raise Framework::HTTP::BadRequest.new("WebSocket RFC 6455 4.2.1.2 requires Host header field") unless request_headers.has_key? "Host"

		raise Framework::HTTP::BadRequest.new("WebSocket RFC 6455 4.2.1.3 requires Upgrade header field") unless request_headers.has_key? "Upgrade"
		raise Framework::HTTP::BadRequest.new("WebSocket RFC 6455 4.2.1.3 requires that Upgrade header field value contains 'websocket' (case insensitive)") unless request_headers["Upgrade"].downcase.include?("websocket")

		raise Framework::HTTP::BadRequest.new("WebSocket RFC 6455 4.2.1.4 requires Connection header field") unless request_headers.has_key? "Connection"
		raise Framework::HTTP::BadRequest.new("WebSocket RFC 6455 4.2.1.4 requires that Connection header field value contains 'upgrade' (case insensitive)") unless request_headers["Connection"].downcase.include?("upgrade")

		raise Framework::HTTP::BadRequest.new("WebSocket RFC 6455 4.2.1.5 requires Sec-WebSocket-Key header field") unless request_headers.has_key? "Sec-WebSocket-Key"
		raise Framework::HTTP::BadRequest.new("WebSocket RFC 6455 4.2.1.5 requires that Sec-WebSocket-Key header field value, when decoded, is a 16-byte string") unless 	Base64.decode64(request_headers["Sec-WebSocket-Key"]).length == 16

		raise Framework::HTTP::BadRequest.new("WebSocket RFC 6455 4.2.1.6 requires Sec-WebSocket-Version header field") unless request_headers.has_key? "Sec-WebSocket-Version"
		raise Framework::HTTP::BadRequest.new("WebSocket RFC 6455 4.2.1.6 requires that Sec-WebSocket-Version header field is value '13'") unless request_headers["Sec-WebSocket-Version"] == "13"

		# RFC 6455 4.2.2: Sending the Server's Opening Handshake; Section 5
		
		# compute response for WebSocket
		computed_key = Digest::SHA1.base64digest(request_headers["Sec-WebSocket-Key"] + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11")

		out_headers =  "HTTP/1.1 101 Switching Protocols\r\n"
		out_headers << "Upgrade: websocket\r\n"
		out_headers << "Connection: Upgrade\r\n"
		out_headers << "Sec-Websocket-Accept: #{computed_key}\r\n"
		out_headers << "Date: #{Time.now}\r\n"
		out_headers << "Server: Ruby WebSocket\r\n"
		out_headers << "\r\n"

		write out_headers

		puts "RESPONSE SENT:" ##
		puts out_headers ##

	end

	def handle_frame

		begin

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
				write encode_frame(opcode:10)

			when 8 # close

				# mirror received close code
				close_code = Framework.byte_string_to_int(payload.slice!(0..1))

				close(code:close_code, reason:payload) # echoes same close reason

			when 1, 2 # start of text or binary message

				message = add_message(payload)

				if fin

					@messages << message
					message.complete
					@on_message.call(message)

				end

				puts "\r\nMESSAGE NUMBER\r\n\r\n#{@message_count}"

			when 0 # continuation

				message << payload
				
				if fin

					@messages << message
					message.complete
					@on_message.call(message)

				end

			end

		rescue => e
			output_string = "#{e.class.name}\n#{e.message}\n#{e.backtrace.join("\n")}"
			puts output_string
			write encode_frame(payload:output_string)

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

	def self.encode_frame(fin: true, opcode: 1, payload:"")

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

	def close(code:, reason:'')
	# code expects integer

		write Framework::WebSocket::Connection.encode_frame(opcode:8, payload:(Framework.int_to_byte_string(code, 2) << reason)) # encode close message

		super()

		@on_close.call(self)

		puts "\r\nCONNECTION CLOSED\r\n\r\n"
		puts "#{code}: #{reason}"

	end

	def add_message(msg)

		@message_count += 1
		Framework::WebSocket::Message.new(self, msg)

	end

end # Framework::WebSocket::Connection

class Framework::WebSocket::Message

	attr_reader :content, :connection, :server, :format
	
	def initialize(connection, message = "")
		
		@connection = connection
		@server = connection.server
		@content = nil
		@complete = false
		@buffered_content = message
				
	end

	def <<(string)

		@buffered_content << string

	end

	def complete

		@content = @buffered_content
		@buffered_content = nil
		@complete = true

		puts "MESSAGE CONTENT:\r\n\r\n"
		puts @content
	end		

	def to_json

		return EXTENSIONS["json"] + JSON.generate(@content)

	end		

end # Framework::WebSocket::Message