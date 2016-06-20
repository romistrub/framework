require_relative("../framework")

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

class Framework::WebSocket::Server < Framework::Server

	def socket_class
		Framework::WebSocket::Connection
	end

	def accept(*args)
		super(*args)
		puts "connections: @connections.length" ##
	end

end # Framework::WebSocket::Server

class Framework::WebSocket::Connection < Framework::Connection

	attr_reader :message_count, :messages
	attr_reader :page

	def initialize(socket:, server:, handlers:{})

		super(socket:socket,server:server)

		@message_count = 0
		@messages = []

		@on_open = handlers[:on_open] || proc {}
		@on_message = handlers[:on_message] || proc {}
		@on_close = handlers[:on_close] || proc {}

		@page = nil

		handshake_response(@request_headers)

		@socket_open = true
		@on_open.call(self)

		# receive messages
		Thread.new {

			while @socket_open do

				handle_frame

			end

		}
	end

	def handshake_response(request_headers)

		if defined? request_headers["Sec-WebSocket-Key"]

			# compute response for WebSocket
	
			websocket_key = request_headers["Sec-WebSocket-Key"]
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
					message.complete	# parses message using extension specified by first bit
					@on_message.call(message)

				end

				puts "\r\nMESSAGE NUMBER\r\n\r\n#{@message_count}"

			when 0 # continuation

				message << payload

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

	def encode_frame(fin: true, opcode: 1, payload:"")

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

		write encode_frame(opcode:8, payload:(Framework.int_to_byte_string(code, 2) << reason)) # encode close message

		super()

		@on_close.call(self)

		puts "\r\nCONNECTION CLOSED\r\n\r\n"
		puts "#{code}: #{reason}"

	end

	def add_message(msg)

		@message_count += 1
		Framework::WebSocket::Message.new(self, msg)

	end

	def link_page(page)
		@page = page
	end

end # Framework::WebSocket::Connection

class Framework::WebSocket::Message

	attr_reader :content, :connection, :server, :format

	FORMATS = {
		"\x00" => "plaintext",
		"\x01" => "json",
		"\x06" => "initialize"
	}

	EXTENSIONS = FORMATS.invert
	
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

		formats = Framework::WebSocket::Message::FORMATS

		if @server.options[:allow_extensions]
			@format = (formats.has_key?(@buffered_content[0])) ? formats[@buffered_content.slice!(0)] : "plaintext"
		end
		
		case @format
		when "initialize", "plaintext"
			@content = @buffered_content
		when "json"
			@content = JSON.parse(@buffered_content)
		end

		@buffered_content = nil
		@complete = true

		puts "MESSAGE FORMAT: #{@format}\r\n\r\n"
		puts "MESSAGE CONTENT:\r\n\r\n"
		ap @content
	end		

	def to_json

		return EXTENSIONS["json"] + JSON.generate(@content)

	end		

end # Framework::WebSocket::Message