# Players table set-up script
#database: framework
#user: romistrub@localhost
#password: !E?U-ehaTRE5av75

require 'mysql2'

options={
	database: "framework",
	host: "localhost",
	username: "romistrub",
	password: "abcd"
}

puts options

client = Mysql2::Client.new(options)

puts client.query("CREATE TABLE players (id INT NOT NULL primary key AUTO_INCREMENT);")
