require_relative("../framework/http")
require_relative("../framework/web_socket")
require 'mysql2'
require 'json'
require 'erb'

class Framework::Site

	attr_reader :http_server, :websocket_server
	attr_reader :name
	attr_reader :interfaces
	attr_accessor :interfaces_by_connection
	attr_accessor :apps, :app_id
	attr_reader :users
	attr_reader :database
	
	WEBSOCKET_FORMATS = {
		"default" => "plaintext",
		"\x00" => "plaintext",
		"\x01" => "json",
		"\x06" => "initialize"
	}
	WEBSOCKET_EXTENSIONS = WEBSOCKET_FORMATS.invert

	def initialize(name:'', database_info:)

		@http_server = Framework::HTTP::Server.new(name:"HTTP", port:80, site:self)
		@websocket_server = Framework::WebSocket::Server.new(name:"WebSocket", port:9292, site:self)

		@name = name

		@interfaces = {} # by ticket
		@interfaces_by_connection = {}
		@users = {} # by name
		@apps = {} # by id
		@app_id = 1
		
		@database = Mysql2::Client.new(database_info)
		
		websocket_handlers = {
			on_close: proc {|connection|
				remove_interface(connection)
			},
			on_message: proc {|message|
				route_message(message)
			}
		}

		http_handlers = {

			on_request: proc {|connection|

				uri = connection.request_headers["URI"]
				
				document_root = "www"
				index = "index.htm"
				
				file_path = (uri == "/") ? document_root + "/" + index : (document_root + uri)
				file_path = File.absolute_path file_path
				
				erb_file = File.exist?(file_path + ".erb")
				regular_file = File.exist?(file_path)
				file_extension = File.extname file_path
				file_path = file_path + ".erb" if erb_file
				
				if erb_file or regular_file
				
					t = (connection.remote_ip + ":" + connection.remote_port.to_s + "; " + Time.now().to_s + "; " + Random.new_seed.to_s)
					interface = add_interface(ticket: t, creation_time: Time.now())
				
					output = File.read(file_path)
					
					ap uri.split("/")
					if uri.split("/")[1] == "app"
						app_id = connection.request_headers["GET"]["id"]
						puts "\n\n\n\n\n\n\n\n\n\n\n\n\n\nAPP_ID = " + app_id
						binding = @apps[app_id.to_i()].get_binding()
					else
						puts "\n\n\n\n\n\n\n\n\n\n\n\n\n\n NOT an APP"
						binding = interface.get_binding()
					end

					output = (ERB.new output).result(binding) if erb_file
					
					extension_list = Framework::HTTP::FILE_EXTENSIONS

					headers = {}
					headers["Content-Type"] = extension_list[file_extension] if extension_list.has_key? file_extension

					connection.respond status_code:200, headers:headers, payload:output

				else
					connection.respond status_code:404, payload:"file not found: #{file_path}"
				end

			}	
			
		}

		# WebSocket Server Loop
		Thread.new {
			loop { websocket_connection = @websocket_server.accept websocket_handlers }
		}

		# HTTP Server Loop
		loop { http_connection = @http_server.accept http_handlers }

	end
	
	def echo(*args)
		args
	end
	
	def get_sister_interfaces(interface)
		@interfaces_by_connection.values().reject{|i| i == interface}
	end
	
	def self.serialize_hash(h)
	
		h.collect{|k,v|
			v = "'#{v}'" if v.class == String
			"#{k}=#{v}"
		}.join(", ")
	
	end
	
	def add_row(table, row_data)
		query = "INSERT #{table} SET #{Framework::Site.serialize_hash(row_data)}"
		@database.query(query)
	end
	
	def add_user(row_data)
		add_row("users", row_data)
	end
	
	def user_exists?(name)
		query = "SELECT * FROM users WHERE name='#{name}'"
		result = @database.query(query)
		return result.size >= 1
	end

	def get_user(name)
		query = "SELECT * FROM users WHERE name='#{name}'"
		result = @database.query(query)
		result.first.delete("password")
		return result.first || nil
	end
	
	def update_user(name, row_data)
		query = "UPDATE users SET #{Framework::Site.serialize_hash(row_data)} WHERE name='#{name}'"
		result = @database.query(query)	
	end
	
	def delete_user(name)
		query = "DELETE FROM users WHERE name='#{name}'"
		@database.query(query)
	end
	
	def logout_user(username)
		user = @users.delete(username)
		if user
			user.interfaces.each {|interface| interface.user = nil}
			user.interfaces = []
			return true
		else
			return false
		end
	end
	
	def user_logged_in?(username)
		@users.has_key?(username)
	end
	
	def add_interface(ticket:, creation_time:)
		@interfaces[ticket] = Framework::Site::Interface.new(site: self, ticket:ticket)
	end
	
	def remove_interface(connection)
		interface = @interfaces_by_connection.delete connection
		if interface
			@interfaces.delete_if {|key,value| value == interface}
			@users.each {|username,user| 
				user.interfaces.delete interface
				if user.interfaces.empty?
					logout_user(username)
				end
			}
		end
	end
	
	def route_message(message)
		connection = message.connection
		content = message.content
		
		wsf = WEBSOCKET_FORMATS
		# if the first character is in the list of WebSocket formats, set format to hash value of first character, otherwise set to default
		format = (wsf.has_key?(content[0])) ? wsf[content.slice!(0)] : wsf["default"]

		# if this is the first message, make sure it's an initialization message, else close the connection
		if connection.message_count == 1											# if this is the first message on this connection
			ticket = content																# the message content should be the ticket supplied by the HTTP server
			if (format == "initialize") and (@interfaces.has_key? ticket)		# check that this message is in the INITIALIZATION format, and that there is an interface corresponding to the ticket
				@interfaces[ticket].bind_connection(connection)				# bind the connection to the interface corresponding to the ticket
			else
				connection.close(code:1000)
			end
		else
			@interfaces_by_connection[connection].route(format, content)
		end
	end

end # Framework::Site

class Framework::Site::Interface

	attr_reader :connection, :site, :ticket
	attr_reader :callbacks
	attr_accessor :user
	
	def initialize(site:, ticket:)

		@site = site
		@ticket = ticket
		@connection = nil
		@user = nil
		@callbacks = []
		@callback_id = 1
		@apps = {}
		
	end

	def bind_connection(connection)
		@connection = connection
		@site.interfaces_by_connection[connection] = self
	end	
	
	def new_app(name, config)
		# translate app name into app object
		app = Framework::App::FROM_NAME[name].new(site:@site, id:@site.app_id, config:config)
		# link App <> Site
		@site.apps[@site.app_id] = app
		# link App <> Interface
		@apps[@site.app_id] = app
		app.interfaces_by_connection[@connection] = self
		
		@site.app_id = @site.app_id + 1
		return @site.app_id - 1
	end
	
	def join_app(username, app_id)
		# check to make sure user is logged on
		if @site.user_logged_in?(username)
			# add user to app
			@site.apps[app_id.to_i()].add_user @site.users[username]
			# add app to user
			@site.users[username].add_app @site.apps[app_id.to_i()]
			return true
		else
			return false
		end
	end
	
	def send(payload)
		puts "SENDING " + payload
		frame = Framework::WebSocket::Connection.encode_frame(payload: payload)
		@connection.write frame
	end
	
	def sendJSON(object)
		send Framework::Site::WEBSOCKET_EXTENSIONS["json"] + JSON.generate(object)
	end
	
	def sendJSONRPC(method, params, &callback)
		@callbacks[@callback_id] = callback
		sendJSON({
			jsonrpc: "2.0",
			method: method,
			params: params,
			id: @callback_id
		})
		@callback_id = @callback_id + 1
	end
	
	def forward(args)
		case args["to"]
		when "site"
			sisters = @site.get_sister_interfaces(self)
		else
			sisters = []
		end
		
		sisters.each{|i|
			i.sendJSONRPC(args["method"], args["params"]) {|json|
				json["forward"] = true
				json["id"] = args["id"]
				self.sendJSON(json)
			}
		}
		return true
	end
	
	def route(format, content)
		case format
		when "json"
			route_json(JSON.parse(content))
		else
			send content
		end
	end
	
	def route_json(content)
		ap content
		if (content.class == Hash) && (content.has_key? "jsonrpc")
			route_jsonrpc(content)
		else
			sendJSON content
		end
	end
	
	def route_jsonrpc(content)
		if content.has_key? "method"
			rpc(content)
		elsif content.has_key? "result"
			callback(content)
		end
	end
	
	def rpc(content)
		method = content["method"]
		args = content["params"]
		args[0]["id"] = content["id"] if method == "forward"
		puts args
		sendJSON({
			jsonrpc: content["jsonrpc"],
			result: route_procedure[method].call(*args),
			id: content["id"]
		})
	end
	
	def callback(content)
		@callbacks[content["id"]].call(content)
		@callbacks.delete(content["id"])
	end
	
	def login_user(username, password)
	
		query = "SELECT * FROM users WHERE name='#{username}' AND password='#{password}'"
		result = @site.database.query(query)
		
		if result.size == 1
			if @site.users.has_key? username
				user = @site.users[username]
			else
				user = Framework::Site::User.new(name: username)
				@site.users[username] = user
			end
			@user = user
			user.interfaces.push self
			return true
		else
			return false
		end
	
	end
	
	def get_binding()
		binding()
	end
	
	def route_procedure
		{
			"add_user" => @site.method("add_user"),
			"user_exists?" => @site.method("user_exists?"),
			"get_user" => @site.method("get_user"),
			"update_user" => @site.method("update_user"),
			"delete_user" => @site.method("delete_user"),
			"login_user" => self.method("login_user"),
			"user_logged_in?" => @site.method("user_logged_in?"),
			"logout_user" => @site.method("logout_user"),
			"forward" => self.method("forward"),
			"echo" => @site.method("echo"),
			"new_app" => self.method("new_app"),
			"join_app" => self.method("join_app")
		}				
	end

end # Framework::Site::Page

class Framework::Site::User

	attr_reader :name, :apps
	attr_accessor :interfaces
	
	def initialize(name:)
		@name = name
		@interfaces = []
		@apps = {}
	end
	def add_app(app)
		@apps[app.id] = app
	end
	
end # Framework::Site::User

class Framework::App

	attr_reader :id, :users
	attr_accessor :interfaces_by_connection
	
	def initialize(site:, id:, config:)
		@site = site
		@id = id
		@config = config
		@users = {}
		@name = "App"
		@interfaces_by_connection = {}
	end
	
	def add_user(user)
		@users[user.name] = user
	end
	
	def get_binding()
		binding()
	end
	
	class Framework::App::Scrabble < Framework::App

		attr_reader :max_players

		def initialize(args)
			super(args)
			@name = "Scrabble"
			@max_players = args[:config]["max_players"]
		end

	end # Framework::App::Scrabble
	
	FROM_NAME = {
		"Scrabble" => Framework::App::Scrabble
	}
	
end # Framework::App