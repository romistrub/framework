#!/usr/bin/env ruby

# SuperServer script.

# Monitor HTTP traffic

##sudo -s #export GEM_PATH= #export PATH=

#    N O A H
#   H S M Y M
#  A R P C S D > pcadrs
#     S L H
#     Y B R  <<
#     P L G & I Q T N
#     S R G
#    N H O R
#     T R H
#    A B R M
#    Y Z H Q
#    I Y Q B
#      1 2

# harbor
# port

# server with name and port, and onrecv trigger
# bidirectional relay
# encapsulation for tcp server with parent and children
class YBR
	@@host = "localhost"
	attr_accessor :children, :parent
	attr_reader :name, :host, :port, :connections, :time
	attr_writer :onrecv
	def initialize (name, port, &onrecv)
		@parent = nil
		@children = []

		@name = name
		@port = port
		@host = @@host
		@onrecv = onrecv
		@time = Time.now
		@connectionClass = Connection
		@connections = []
		@server = TCPServer.new @@host, @port
		puts "#{Time.now} SERVER STARTED (name: #{@name}, port #{@port})\n\n" ##

		Thread.new {
			begin
				loop {
					connection = addConnection
					fireonrecv connection
				}
			rescue Exception => e
				puts e.message
				puts e.backtrace
			end
		}

	end
	def fireonrecv (*args)
		if defined? @onrecv
			@onrecv.call *args
		end		
	end
	def addConnection
		connection = @connectionClass.new(@server.accept, self)
		connection
	end
	def getBinding
		binding()
	end
	def addChild(child)
		child.parent = self
		@children << child
		child
	end
end

# websocket variant of YBR
# bidirectional relay
class BR < YBR
	@@idPrefix
	attr_accessor :frameTime, :frameRecvTime, :frameSendTime
	attr_writer :onopen, :onclose, :onrecvFrame, :onsendFrame
	attr_reader :connections
	def initialize(name, port, &onrecvFrame)
		@onrecvFrame = onrecvFrame
		super(name, port) {|connection| 
			connection.id = getNewID()
			connection.handshake()
		}
		@connectionClass = BRConnection
		@tryCount = -1
		@outstandingRequests = {}
		@fulfilledRequests = []
	end
	def getNewID
		@@idPrefix + @connections.length
	end
	def computeResponseKey(key)
		keysuffix = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
		Digest::SHA1.base64digest(key + keysuffix)
	end
	def onrecvFrame (connection, frame)
		if @onrecvFrame
			@onrecvFrame.call connection, frame
		end
	end
	def addFwd(connection1, connection2)
		# e.g. ybr.brs => array of [BR]
		#      ybr.brs[0].connections => array of [BRConnection]
		#      ybr.brs[0].addFwd(ybr.brs[0].connections[0], ybr.brs[0].connections[1])
		connection1.onrecvFrame= proc {|connection, frame|
			connection2.sendFrame(frame["opcode"], frame["message"])
		}
	end
end

class Connection # HTTP request
	attr_reader :connection, :server, :time, :headerString, :headers, :remote_ip, :remote_port
	@@codes = {
		100 => "Continue",
		101 => "Switching Protocols",
		200 => "OK",
		201 => "Created",
		202 => "Accepted",
		203 => "Non-Authoritative Information",
		204 => "No Content",
		205 => "Reset Content",
		206 => "Partial Content",
		300 => "Multiple Choices",
		301 => "Moved Permanently",
		302 => "Found",
		303 => "See Other",
		304 => "Not Modified",
		305 => "Use Proxy",
		306 => "",
		307 => "Temporary Redirect",
		401 => "Unauthorized",
		402 => "Payment Required",
		403 => "Forbidden",
		404 => "Not Found",
		405 => "Method Not Allowed",
		406 => "Not Acceptable",
		407 => "Proxy Authentication Required",
		408 => "Request Timeout",
		409 => "Conflict",
		410 => "Gone",
		411 => "Length Required",
		412 => "Precondition Failed",
		413 => "Request Entity Too Large",
		414 => "Request-URI Too Long",
		415 => "Unsupported Media Type",
		416 => "Requested Range Not Satisfiable",
		417 => "Expectation Failed",
		500 => "Internal Server Error",
		501 => "Not Implemented",
		502 => "Bad Gateway",
		503 => "Service Unavailable",
		504 => "Gateway Timeout",
		505 => "HTTP Version Not Supported"
	}
	def initialize(id, tcpSocket, server)
		@id = id
		@connection = tcpSocket
		@server = server
		@server.connections << tcpSocket
 		@remote_ip = tcpSocket.remote_address.ip_address
		@remote_port = tcpSocket.remote_address.ip_port
		@time = Time.now

		@headerString = @connection.recv(1024)
		puts "#{Time.now} REQUEST RECEIVED (server:#{server.name}, ##{server.connections.length}, port:#{server.port}, from:#{remote_ip}:#{remote_port})" ##
		lines = @headerString.split("\r\n")
		topLine = lines.shift
		topLineWords = topLine.split(" ")
		@headers = {
			"Method" => topLineWords[0],
			"URI" => topLineWords[1],
			"Protocol" => topLineWords[2]
		}
		lines.each {|line|
			keyval = line.split(": ")
			@headers[keyval[0]] = keyval[1]
		}
		h = @headers
		puts "#{Time.now} REQUEST INFO (#{topLine}, host:#{h['Host']})\n\n"
	end
	def close
		@connection.close
	end
	def write(string)
		@connection.write(string)
	end
	def respond(statusCode, headers = {}, string = '')
		status = @@codes[statusCode]
		statusLine = "HTTP/1.1 #{statusCode} #{status}"
		output = statusLine.clone + "\r\n"
		headers.each{|key, value|
			output << "#{key}: #{value}\r\n"
		}
		output << "\r\n"
		output << string
		write output

		contentTypeLine = ""
		if headers.has_key? "Content-Type"
			contentTypeLine = ", content-type:#{headers["Content-Type"]}"
		end

		puts "#{Time.now} RESPONSE SENT (server:#{server.name}, port:#{server.port}, to:#{remote_ip}:#{remote_port}, length:#{output.length})" ##
		puts "#{Time.now} RESPONSE INFO (status:#{statusLine}#{contentTypeLine})\n\n"
	end
end

## Bidirectional Relay Connection
class BRConnection < Connection
	attr_writer :onrecvFrame, :onsendFrame, :onopen, :onclose
	attr_reader :frameSendTime, :frameRecvTime, :frameTime
	attr_accessor :id, :state
	def initialize(connection, server, &onrecvFrame)
		super(connection, server)
		@onrecvFrame = onrecvFrame
		@state = :closed
		@frameSendTime = nil
		@frameRecvTime = nil
		@frameTime = nil
		@frames = []
	end
	def handshake
		key = @headers["Sec-WebSocket-Key"]
		if defined? key
			puts "#{Time.now} HANDSHAKE RECEIVED (Sec-WebSocket-Key:#{key})"
			responseKey = computeResponseKey(key)
			puts "#{Time.now} HANDSHAKE RESPONSE (Sec-Websocket-Accept:#{responseKey})"

			respond 101, {
				"Connection"	=> "Upgrade",
				"Date"		=> Time.now,
				"Server"	=> "#{parent.name}/#{name}",
				"Upgrade"	=> "WebSocket",
				"Sec-WebSocket-Accept" => responseKey
			}

			@state = :open
			fireonopen(connection)

			Thread.new {
				begin
					loop {
						frame = connection.recvFrame
						connection.onrecvFrame frame
					}
				rescue Exception => e
					puts e.message
					puts e.backtrace
				end
			}

		else
			## connection.write "websocket error"
			puts "#{TIme.now} HANDSHAKE ERROR (no Sec-WebSocket-Key in request header)\n\n"
		end

	end
	def fireon(type, *args)
		eventType = "on"+type
		if self.instance_variables.has_key? eventType
			self.instance_variables_get[eventType].call(*args)
		end
		if server.instance_variables.has_key? eventType
			server.instance_variables_get[eventType].call(*args)
		end
	end
	def fireonopen(*args) on("open") end
	def fireonclose(*args) on("close") end
	def fireonrecvFrame(*args) on("recvFrame") end
	def fireonsendFrame(*args) on("sendFrame") end
	def push(signal, query, args, &callback)
		i = @tryCount + 1
		o = {"m"=>"push", "p"=>"try", "i"=>i,
			"s"=>signal,
			"q"=>query,
			"a"=>args
		}
		@outstandingRequests[i] = [o, callback]
		sendMessage(o)
	end
	# signal handler: update
	def sendMessage(o)
		o["t"] = (Time.now.to_f*1000).to_s
		m = JSON.generate(o)
		connection.sendFrame(m)
	end
	def recvMessage(m)
		o = JSON.parse(m)
		self.send("p_"+o["p"])
	end
	# {m:"push", p:"try", i:i, s:"set"|"get". q:"id"|"state"|.., t:Time.now, a:{state}}
	def p_try(o)
		functionName = o["s"] + "_" + o["q"]
		if !self.respond_to?(functionName)
			o["a"] = "!failed (" + functionName + " is undefined)";
		else
			o["a"] = self.send(functionName, o)
		end
		o["p"] = "rtn"
		sendMessage(o)
	end
	def p_rtn(o)
		req @outstandingRequests.delete o["i"]
		@fulfilledRequests << [req, o, o["t"]-req["t"]]
		req[1].call(o)
	end
	def set_id(o)
		@id = o["a"]
		"!success"
	end
	def get_id(o) @id end
	def recvFrame

#puts "\n\n\nGOAL\n\n\n" ####
		header = @connection.recv(2)
		bytes = header.bytes
		byteone = bytes.shift
		opcode = byteone-128 # remove very first bit (set to one for finbit)
		if opcode == 8
			@connection.close
			m = "connection closed"
		elsif opcode == 1
			bytetwo = bytes.shift
			masked = bytetwo[7]
			length = bytetwo
			if masked
				payloadlength = length-128 # negate mask flag bit
				bodylength = payloadlength+4 #+4 from mask bytes
			end
			body = @connection.recv(bodylength)
			bytes = body.bytes
			if masked
				mask = bytes.shift 4
			end
			payload = bytes.shift length
			rawpayload = payload
			if masked
				payload = payload.map.with_index{|byte, i|
					mask[i%4]^byte
				}
			end
			# payload may be nil for message: ""
			m = message = payload.map {|n| n.chr}.join('')
			
			frame = {
				"time"=>Time.now,
				"opcode"=> opcode,
				"masked"=> masked,
				"payloadlength"=> length,
				"mask"=>mask,
				"payload"=>rawpayload,
				"message"=>message,
				"length"=>bodylength+2
			}
		end
		puts "#{Time.now} WS FRAME RECEIVED (server:#{server.name}, port:#{server.port}, from:#{remote_ip}:#{remote_port}, opcode:#{opcode}, message:#{m})\n\n"

		frameRecvTime = @server.frameRecvTime = frameTime = @server.frameTime = Time.now
		@frames << frame
		fireonrecvFrame self, frame
		frame
	end
	def sendFrame(opcode, message)
		@connection.write (128 + opcode).chr << message.length.chr << message
		puts "#{Time.now} WS FRAME SENT (server:#{server.name}, port:#{server.port}, to:#{remote_ip}:#{remote_port}, opcode:#{opcode}, message:#{message})\n\n"
		@frameSendTime = @server.frameSendTime = @frameTime = @server.frameTime = Time.now
		fireonsendFrame self, {"opcode"=>opcode,"message"=>message}
	end
	def close
		@connection.close
		fireonclose self
	end
end

puts "\n#{Time.now} YBR STARTED (Ruby version:#{RUBY_VERSION}, PID:#{Process.pid})\n\n"

require 'digest/sha1'
require 'socket'
require 'awesome_print'
require 'erb'

begin

	ybr = YBR.new("ybr", '80'){|connection|

		uri = connection.headers["URI"]
		
		if uri == "/"
			template = File.read("br.html.erb")
			output = (ERB.new template).result(mbr.getBinding)
			connection.respond 200, {"Content-Type"=>"text/html"}, output
		else 
			path = uri.split("/")
			path.shift
			firstDir = path.shift

			# return links of the form :port/br/name		
			if firstDir == "br" # form of url = br/name/subname/subsub
				brName = path.shift
				br = ybr.addChild YBR.new(brName, "9292")
				
				template = File.read("br.html.erb")
				output = (ERB.new template).result(br.getBinding)
				connection.respond 200, {"Content-Type"=>"text/html"}, output
			else
				localpath = "." + uri
				if File.exist?(localpath)
					ext = File.extname(localpath)
					filetypes = {
						".js" => "text/javascript",
						".css" => "text/css",
						".htm" => "text/html",
						".html" => "text/html",
						".ico" => "image/x-icon"
					}
					if filetypes.has_key? ext
						header = {"Content-Type"=>filetypes[ext]}
					else
						header = {}
					end
					connection.respond 200, header, File.read(localpath)
				else
					connection.respond 404, {}, "404: not found"
				end

			end
		end

		connection.close

	}

	mbr = ybr.addChild(BR.new("mbr", '9292'))

# operator
	operatorSocketName = "/tmp/ybr-oper2"
	operatorServer = UNIXServer.new(operatorSocketName)
	operatorSocket = operatorServer.accept


	loop {
			input = operatorSocket.recv(1024)
			puts "input: " + input
			output = eval(input)
			if output == nil
				output = "no output"
			end
			puts "output: " + output.to_s
			operatorSocket.send(output.to_s,0)
	}

rescue Exception => e
	puts e
ensure
	File.delete operatorSocketName
end
