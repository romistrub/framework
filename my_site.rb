require_relative("framework/site")

site = Framework::Site.new(database_info:{
	database: "framework",
	host: "localhost",
	username: "romistrub",
	password: "abcd"
})

