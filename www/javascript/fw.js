var FW = {

	connection: function(host, ticket, o){
		var socket = new WebSocket(host,[]);
		var that = {};
		var callbacks = [];
		var oo = o || function(){};
		
		socket.onopen = function(){
			console.log("readyState: " + socket.readyState);
			socket.send("\x06" + ticket);  // send initialization signal (ASCII 'ACKNOWLEDGE')
			oo.apply(that);
		}
	
		socket.onmessage = function(e) {
			var message = e.data;
			var firstChar = message.charCodeAt(0)
			var response;
			
			console.log("receieve: " + message);
			console.log("first character code point is: " + firstChar);

			// check for JSON prefix
			if (firstChar == 1) {
			
				console.log("JSON detected");
				
				message = message.slice(1);
				
				json = JSON.parse(message);
				
				console.log(JSON.stringify(json, null, 2));
				
				if (json.hasOwnProperty("jsonrpc")) {
					if (json.hasOwnProperty("result")) {
						if (json.hasOwnProperty("id")) {
							callbacks[json.id - 1].apply(that, [json]);
						}
					} else if (json.hasOwnProperty("method")) {
						if (that.rpcMethods.hasOwnProperty(json.method)) {
							response = {
								jsonrpc: "2.0",
								result: that.rpcMethods[json.method].apply(that, json.params)
							}
							if (json.hasOwnProperty("id")) {
								response.id = json.id
							}
							that.sendJSON(response);
						}
					}
				}
			}
			
		};
	
		that = {
			readyState: function(){
				return socket.readyState
			},
			send: function(string) {
				console.log("send: " + string);
				socket.send(string);
			},
			sendJSON: function(object) {
				that.send("\x01" + JSON.stringify(object));
			},
			sendJSONRPC: function(method, params, callback) {
				callbacks.push(callback || function(){});
				that.sendJSON({
					"jsonrpc":"2.0",
					"method":method,
					"params":params,
					"id":callbacks.length
				});
			},
			close: function() {
				socket.close(arguments);
			},
			rpcMethods: {}
		};
		return that
	}
}