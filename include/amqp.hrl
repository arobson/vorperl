-include("amqp_client.hrl").

-record(broker, {
	name,
	params=#amqp_params_network{},
	connection
}).

-record(envelope, {
	id,
	exchange, 
	queue, 
	key, 
	correlation_id,
	content_type,
	content_encoding,
	type,
	headers, 
	body, 
	ack, 
	nack, 
	reply,
	timestamp,
	user_id,
	app_id,
	cluster_id}).