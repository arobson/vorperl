-record(broker, {
	user="guest", 
	password="guest", 
	host="localhost", 
	virtual_host="/", 
	port=5672, 
	max_channels=0, 
	max_frames=0, 
	heartbeat=0, 
	ssl_options={}, 
	auth=[], 
	client={}}).

-record(envelope, {exchange, queue, key, content_type, body, ack, nack, reply}).

-record(message_flags, {
	id, 
	key= <<"">>, 
	mandatory=false, 
	immediate=false, 
	reply_to=undefined}).

-record(exchange_config, {
	type = <<"direct">>, 
	durable=false, 
	auto_delete=true, 
	exclusive=false}).

-record(queue_config, {
	durable=false, 
	persistent=false, 
	auto_delete=true}).

-record(topology, {
	exchange=undefined, 
	exchange_config=undefined, 
	queue=undefined, 
	queue_config=undefined, 
	topic= <<"">>}).