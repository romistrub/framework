#!/usr/bin/env ruby

=begin

	Author: Romi Strub
	Last Edited: 19-06-2016 (DD-MM-YYYY)

=end

puts "RUBY_VERSION #{RUBY_VERSION}"
puts "Process.pid #{Process.pid}"

Thread.abort_on_exception = true

require 'digest/sha1'
require 'socket'
require 'awesome_print'
require 'json'


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

end # Framework

class Framework::Server

	attr_reader :name	
	attr_reader :tcp_server, :hostname, :port
	attr_accessor :connection_count, :connections, :connection_history
	attr_reader :options
	attr_reader :site
	
	DEFAULT_OPTIONS = {allow_extensions: true}

	def initialize (name:'', hostname:'', port:80, site:, options: {})
		
		@tcp_server = TCPServer.new(hostname, port)

		@name = name
		@hostname = hostname
		@port = port
		@site = site
		@options = DEFAULT_OPTIONS.merge(options)	

		@connection_count = 0
		@connections = []
		@connection_history = []

		puts "server (name: #{@name}) started on port #{@port}" ##

		puts "\r\nSTART TESTS"
		#puts MyWebSocket.bytes_to_int([0,0,1])
		puts "END TESTS\r\n"

	end

	def accept(handlers)

		socket = @tcp_server.accept

		socket_class.new(socket:socket, server:self, handlers:handlers)

	end
	
	def socket_class
		Framework::Connection
	end

	def remove_connection(connection)

		@connection_count -= 1
		@connection_history << connection
		@connections.delete(connection)

	end

	def get_connection_number(connection)

		@connections.find_index(connection) + 1

	end

end # Framework::Server

class Framework::Connection

	attr_reader :socket, :server
	attr_reader :request_headers
	attr_reader :remote_ip, :remote_port
	attr_reader :time

	def initialize(socket:, server:)

		@socket = socket
		@server = server

		@server.connection_count += 1
		@server.connections << self

		@remote_ip = @socket.remote_address.ip_address
		@remote_port = @socket.remote_address.ip_port
		@time = Time.now

		puts "connection #{get_connection_number} on server #{@server.name} port #{@server.port}" ##
		puts "local address: #{@socket.addr}"
		puts "remote address: #{@remote_ip}:#{@remote_port}"

		puts "#{@time} REQUEST RECEIVED (server: #{@server.name}, ##{@server.connections.length}, port:#{@server.port}; from: #{@remote_ip}:#{@remote_port})" ##
		@request_headers = Framework::parse_http_headers(@socket.recv(1024))
		ap @request_headers ##

	end

	def close

		@socket.close

		@server.remove_connection(self)

		@socket_open = false

	end

	def recv(bytes)
		@socket.recv(bytes)
	end

	def write(content)
		@socket.write(content)
	end

	def get_connection_number
		@server.get_connection_number(self)
	end

end # Framework::Connection

