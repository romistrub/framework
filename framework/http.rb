require_relative("../framework")

module Framework::HTTP

	FILE_EXTENSIONS = {
		".js" => "text/javascript",
		".css" => "text/css",
		".htm" => "text/html",
		".html" => "text/html",
		".ico" => "image/x-icon"
	}

end

class Framework::HTTP::Server < Framework::Server

	def socket_class
		Framework::HTTP::Request
	end

end # Framework::HTTP::Server

class Framework::HTTP::Request < Framework::Connection

	CODES = {
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

		attr_reader :on_request

	def initialize(socket:, server:, handlers:{})

		super(socket:socket,server:server)

		@on_request = handlers[:on_request] || proc {}

		@on_request.call(self)

		close

	end

	def respond(status_code:, headers:{}, payload:'')

		status_line = "HTTP/1.1 #{status_code} #{CODES[status_code]}"

		output = "#{status_line}\r\n"

		headers.each{|key, value|
			output << "#{key}: #{value}\r\n"
		}

		output << "\r\n#{payload}"

		write output

		puts "#{Time.now} RESPONSE SENT (server:#{server.name}, port:#{server.port}, to:#{remote_ip}:#{remote_port}, length:#{output.length})" ##
		puts "#{Time.now} RESPONSE INFO (status:#{status_line} #{headers['Content-Type']})\n\n"
		
	end
	
end

