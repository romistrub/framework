require_relative("../framework/http")
require_relative("../framework/web_socket")

class Framework::Site

	attr_reader :http_server, :websocket_server
	attr_reader :name
	attr_reader :pages

	def initialize(name:'')

		@http_server = Framework::HTTP::Server.new(name:"HTTP", port:80, site:self)
		@websocket_server = Framework::WebSocket::Server.new(name:"WebSocket", port:9292, site:self)

		@name = name

		@pages = []


	end

	def add_page(connection)

		@pages << Framework::Site::Page.new(site: self, connection: connection)

	end

end # Framework::Site

class Framework::Site::Page

	attr_reader :connection, :site

	def initialize(site:, connection:)

		@site = site
		@connection = connection
		connection.link_page(self)

	end

end # Framework::Site::Page
