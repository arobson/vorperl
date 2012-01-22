-record(broker, {
	name= <<"default">>,
	user= <<"guest">>, 
	password= <<"guest">>, 
	host= "localhost", 
	virtual_host= <<"/">>, 
	port=5672, 
	max_channels=0, 
	max_frames=0, 
	heartbeat=0, 
	ssl_options=none, 
	auth=[], 
	client={},
	connection=undefined}).

-record(envelope, {
	exchange, 
	queue, 
	key, 
	correlation_id,
	content_type,
	content_encoding,
	headers=[], 
	body, 
	ack, 
	nack, 
	reply,
	timestamp,
	user_id,
	app_id,
	cluster_id}).

-record(message_flags, {
	id, 
	correlation_id,
	key= <<"">>,
	content_type,
	content_encoding,
	headers=[],
	persist=false,
	mandatory=false, 
	immediate=false,
	reply_to=undefined,
	expiration,
	timestamp,
	user_id,
	app_id,
	cluster_id,
	priority}).


%-record('P_basic', {content_type, content_encoding, headers, delivery_mode, priority, correlation_id, reply_to, expiration, message_id, timestamp, type, user_id, app_id, cluster_id}).