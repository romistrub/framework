# Players table set-up script
#database: framework
#user: romistrub@localhost
#old-password: !E?U-ehaTRE5av75
#temp-password: abcd

require 'mysql2'

options={
	database: "framework",
	host: "localhost",
	username: "romistrub",
	password: "abcd"
}

puts options

client = Mysql2::Client.new(options)

#puts client.query("CREATE TABLE players (id INT NOT NULL primary key AUTO_INCREMENT);")

r = client.query("SELECT * FROM users WHERE name='romistrub' AND password='abcd';")
puts r.size