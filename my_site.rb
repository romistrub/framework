require_relative("framework/site")

site = Framework::Site.new

# on_open, on_message, and/or on_close

websocket_handlers = {
	on_message: proc {|message|
	
		connection = message.connection

		# If sending JSON, prepend extension prefix
		case message.format
		when "initialize"
			connection.server.site.add_page(connection)
			return_payload = message.content
		when "json"
			if message.content.has_key? "jsonrpc"
				method = message.content["method"]
				args = message.content["params"]
				connection.page.send(method, *args)
			end
			return_payload = message.to_json
		else
			return_payload = message.content
		end
		
		return_frame = connection.encode_frame(payload: return_payload)
		
		connection.server.connections.each {|c|
			c.write return_frame
		}
	}
}

http_handlers = {

	on_request: proc {|connection|

		uri = connection.request_headers["URI"]

		file_path = (uri == "/") ? "www/index.htm" : File.absolute_path("www" + uri)

		if File.exist? file_path

			output = File.read(file_path)
			#output = (ERB.new template).result(mbr.getBinding)

			file_extension = File.extname file_path
			extension_list = Framework::HTTP::FILE_EXTENSIONS

			headers = {}
			headers["Content-Type"] = extension_list[file_extension] if extension_list.has_key? file_extension

			connection.respond status_code:200, headers:headers, payload:output

		else
			connection.respond status_code:404, payload:"file not found: #{file_path}"
		end

	}	
	
}

Thread.new {
	loop {

		# receive connection
		connection = site.websocket_server.accept websocket_handlers

	}
}

loop {
		connection = site.http_server.accept http_handlers
}
