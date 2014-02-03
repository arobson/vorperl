%%% @author Alex Robson <asrobson@gmail.com>
%%% @copyright Alex Robson 2012
%%% @doc
%%%	Convenience functions for working with amqp. Internalizes all work with records in amqp.hrl.
%%% @end
%%% @license MIT
%%% Created January 20, 2012 by Alex Robson

-module(amqp_util).

-ifdef(TEST).
-compile(export_all).
-endif.

-export([ 
			broker_declare/1,
			exchange_declare/2,
			prep_envelope/4,
			prep_message/4,
			prep_return/2,
			parse_proplist/1,
			proplist_to_table/1,
			queue_declare/2,		
			to_bin/1,
			to_bitstring/1
		]).

-include("amqp.hrl").


%% @doc Handles the creation of a broker record from a proplist. This
%% prevents the user from having to import the amqp.hrl header file
%% and also provides simple defaults for missing arguments where possible.
%% The list of properties are as follows:
%%		auth_mechanism 		default is username & password
%%		channel_max 		max channels allowed. default is 0
%%		client_properties 	client specific properties (a proplist, default is [])
%%		connection_timeout	# of seconds to wait for connection. default is infinity
%%		frame_max			maximum frame size in bytes allowed. default is 0
%%		heartbeat			delay in seconds between heartbeats. default is 0 (no heartbeat)
%%		host 				the rabbit host name/IP as a string. default is "localhost"
%%		password			password for the user. default is "guest"
%%		port 				the broker port. default is 5672
%%		socket_options		
%%		

-spec broker_declare([{atom(),term()}]) -> {string(), #amqp_params_network{}}.

broker_declare(Props) ->
	Default = #amqp_params_network{},
	DefaultAuth = Default#amqp_params_network.auth_mechanisms,
	Params = #amqp_params_network{
			username=parse_prop(user, Props, "guest"),
			password=parse_prop(password, Props, "guest"),
			virtual_host=parse_prop(virtual_host, Props, "/"),
			host=proplists:get_value(host, Props, "localhost"),
			port=parse_prop(port, Props, 5672),
			channel_max=parse_prop(channel_max, Props, 0),
			frame_max=parse_prop(frame_max, Props, 0),
			heartbeat=parse_prop(heartbeat, Props, 0),
			connection_timeout=parse_prop(connection_timeout, Props, infinity),
			ssl_options=parse_prop(ssl, Props, none),
			auth_mechanisms=proplists:get_value(auth, Props, DefaultAuth),
			client_properties=proplists:get_value(client, Props, []),
			socket_options=proplists:get_value(socket, Props, [])
		},
	Params.

delivery_type(Props) ->
	case parse_prop(persist, Props, false) of
		true -> 2;
		_ -> 1
	end.

exchange_declare(Exchange, Config) ->
	#'exchange.declare'{
		exchange=Exchange,
		type=parse_prop(type, Config, "direct"),
		durable=parse_prop(durable, Config, false),
		auto_delete=parse_prop(auto_delete, Config, false),
		passive=parse_prop(passive, Config, false),
		internal=parse_prop(internal, Config, false),
		nowait=parse_prop(nowait, Config, false)
	}.

get_ack(Tag, Channel) ->
	fun() -> amqp_channel:cast(Channel, #'basic.ack'{delivery_tag=Tag}) end.
	
get_nack(Tag, Channel) ->
	fun() -> amqp_channel:cast(Channel, #'basic.nack'{delivery_tag=Tag}) end.

get_reply(Envelope) ->
	ReplyExchange = Envelope#envelope.reply_to,
	Correlation = Envelope#envelope.correlation_id,
	ContentType = Envelope#envelope.content_type,
	Application = Envelope#envelope.app_id,
	Cluster = Envelope#envelope.cluster_id,
	User = Envelope#envelope.user_id,

	Incoming = [
		{correlation_id, Correlation},
		{content_type, ContentType},
		{app_id, Application},
		{cluster_id, Cluster},
		{user_id, User}
	],

	fun(Msg, Key, Props) ->
		CombinedProps = lists:append(Props, Incoming),
		vorperl:send(ReplyExchange, Msg, Key, CombinedProps)
	end.

parse_prop(Prop, Props) ->
	parse_prop(Prop, Props, undefined).
parse_prop(Prop, Props, Default) ->
	to_bin(proplists:get_value(Prop, Props, Default)).

parse_proplist(undefined) -> undefined;
parse_proplist(L) ->
	Unfolded = proplists:unfold(L),
	[{X, to_bin(Y)} || {X,Y} <- Unfolded].

prep_envelope(
		#'basic.deliver'{
				delivery_tag=Tag,
				exchange=Exchange,
				routing_key=Key
		}, 
		#amqp_msg{ payload=Payload, props=Props },
		Queue,
		Channel
	) ->

		Envelope = #envelope{
			exchange=Exchange,
			queue=Queue,
			key=Key,
			body=Payload,
			correlation_id=Props#'P_basic'.correlation_id,
			content_type=Props#'P_basic'.content_type,
			content_encoding=Props#'P_basic'.content_encoding,
			type = Props#'P_basic'.type,
			headers=table_to_proplist(Props#'P_basic'.headers),
			id=Props#'P_basic'.message_id,
			timestamp=Props#'P_basic'.timestamp,
			user_id=Props#'P_basic'.user_id,
			app_id=Props#'P_basic'.app_id,
			cluster_id=Props#'P_basic'.cluster_id,
			reply_to=Props#'P_basic'.reply_to,
			ack=get_ack(Tag, Channel),
			nack=get_nack(Tag, Channel)
		},

		Envelope#envelope{ reply=get_reply(Envelope)}.

prep_return(
		#'basic.return'{
				exchange=Exchange,
				routing_key=Key
		}, 
		#amqp_msg{ payload=Payload, props=Props }
	) ->

		#envelope{
			exchange=Exchange,
			key=Key,
			body=Payload,
			correlation_id=Props#'P_basic'.correlation_id,
			content_type=Props#'P_basic'.content_type,
			content_encoding=Props#'P_basic'.content_encoding,
			type = Props#'P_basic'.type,
			headers=Props#'P_basic'.headers,
			id=Props#'P_basic'.message_id,
			timestamp=Props#'P_basic'.timestamp,
			user_id=Props#'P_basic'.user_id,
			app_id=Props#'P_basic'.app_id,
			cluster_id=Props#'P_basic'.cluster_id
		}.

%content_type, content_encoding, headers, delivery_mode, priority, correlation_id, reply_to, expiration, message_id, timestamp, type, user_id, app_id, cluster_id
prep_message(Exchange, RoutingKey, Props, ExchangeProps) ->
	Headers = parse_proplist(proplists:get_value(headers, Props, [])),
	AmqpProps = #'P_basic'{
		content_type = parse_prop(content_type, ExchangeProps, <<"text/plain">>),
		content_encoding = parse_prop(content_encoding, Props),
		headers = proplist_to_table(Headers),
		delivery_mode = delivery_type(Props),
		priority = parse_prop(priority, Props),
		correlation_id = parse_prop(correlation_id, Props),
		reply_to = parse_prop(reply_to, Props),
		expiration = parse_prop(expiration, Props),
		message_id = parse_prop(id, Props),
		timestamp = parse_prop(timestamp, Props),
		type = parse_prop(type, Props),
		user_id = parse_prop(user_id, Props),
		app_id = parse_prop(app_id, Props),
		cluster_id = parse_prop(cluster_id, Props)
	},
	Publish = #'basic.publish'{ 
		exchange = to_bitstring(Exchange),
		mandatory = parse_prop(mandatory, Props, false),
		routing_key = to_bitstring(RoutingKey)
	},
	{AmqpProps, Publish}.

proplist_to_table(undefined) -> undefined;
proplist_to_table(List) ->
	Parsed = parse_proplist(List),
	lists:map(fun({K, V}) -> 
		NewK = key_to_bitstring(K),
		kvp_to_amqp_field(NewK,V) 
	end, Parsed).

table_to_proplist(undefined) -> undefined;
table_to_proplist(Table) ->
	lists:map(fun({K, _F, V}) -> {K,V} end, Table).

key_to_bitstring(K) when is_atom(K) -> list_to_bitstring(atom_to_list(K));
key_to_bitstring(K) when is_list(K) -> list_to_bitstring(K);
key_to_bitstring(K) when is_bitstring(K) -> K.

kvp_to_amqp_field(K,V) when is_atom(V) -> {K, binary, list_to_bitstring(atom_to_list(V))};
kvp_to_amqp_field(K,V) when is_boolean(V) -> {K, bool, V};
kvp_to_amqp_field(K,V) when is_bitstring(V) -> {K, binary, V};
kvp_to_amqp_field(K,V) when is_float(V) -> {K, float, V};
kvp_to_amqp_field(K,V) when is_integer(V) -> {K, signedint, V};
kvp_to_amqp_field(K,V) when is_list(V) -> {K, array, V};
kvp_to_amqp_field(K,V) when is_binary(V) -> {K, binary, V}.

queue_declare(Queue, Config) ->
	Args = build_args(Config),
	#'queue.declare'{
		queue=Queue,
		exclusive=parse_prop(exclusive, Config, false),
		durable=parse_prop(durable, Config, false),
		auto_delete=parse_prop(auto_delete, Config, false),
		passive=parse_prop(passive, Config, false),
		nowait=parse_prop(nowait, Config, false),
		arguments = Args
	}.

build_args(Config) -> build_args(Config, []).

build_args([], Args) -> Args;
build_args([{alternate, X}|T], Args) ->
	build_args(T, [kvp_to_amqp_field(<<"alternate-exchange">>, to_bitstring(X)) || Args]);
build_args([{dead_letter, X}|T], Args) ->
	build_args(T, [kvp_to_amqp_field(<<"x-dead-letter-exchange">>, to_bitstring(X)) || Args]);
build_args([{dead_letter, X, RK}|T], Args) ->
	DLX = kvp_to_amqp_field(<<"x-dead-letter-exchange">>, to_bitstring(X)),
	DLXRK = kvp_to_amqp_field(<<"x-dead-letter-routing-key">>, to_bitstring(RK)),
	Args1 = [DLX || Args],
	Args2 = [DLXRK || Args1],
	build_args(T, Args2);
build_args([{max_length, M}|T], Args) ->
	build_args(T, [kvp_to_amqp_field(<<"x-max-length">>, M) || Args]);
build_args([{message_ttl, M}|T], Args) ->
	build_args(T, [kvp_to_amqp_field(<<"x-message-ttl">>, M) || Args]);
build_args([{ttl, M}|T], Args) ->
	build_args(T, [kvp_to_amqp_field(<<"x-expires">>, M) || Args]);
build_args([_|T], Args) ->
	build_args(T, Args).

to_bitstring([H|T]) when is_list(H) ->
	[to_bitstring(H)] ++ to_bitstring(T);
to_bitstring([{X,Y}|T]) -> 
	H = {to_bitstring(X), to_bitstring(Y)},
	case T of
		[] -> [H];
		_ -> lists:append([H], to_bitstring(T))
	end;
to_bitstring(X) when is_bitstring(X) -> X;
to_bitstring([]) -> []; %%<<"">>;
to_bitstring(X) when is_list(X) ->
	list_to_bitstring(X);
to_bitstring(X) -> X.

to_bin([]) -> [];
to_bin([{X,Y}|T]) ->
	lists:append([{to_bin(X), to_bin(Y)}], to_bin(T));
to_bin(X) when is_list(X) -> list_to_bitstring(X);
to_bin(X) when is_bitstring(X) -> X;
to_bin(X) -> X.
