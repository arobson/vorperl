%%% @author Alex Robson
%%% @copyright 2012
%%% @doc
%%%
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
			prep_message/3,
			prep_return/2,
			parse_proplist/1,
			proplist_to_table/1,
			queue_declare/2,		
			to_bin/1,
			to_bitstring/1
		]).

-include("amqp.hrl").

broker_declare(Props) ->
	Default = #amqp_params_network{},
	DefaultAuth = Default#amqp_params_network.auth_mechanisms,
	Auth = #amqp_params_network{
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
	#broker{
		name = parse_prop(name, Props, "default"),
		params = Auth
	}.

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
	[{X, to_bitstring(Y)} || {X,Y} <- Unfolded].

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

prep_message(Exchange, RoutingKey, Props) ->
	
	Headers = parse_proplist(proplists:get_value(headers, Props, [])),
	AmqpProps = #'P_basic'{
		content_type = parse_prop(content_type, Props, <<"text/plain">>),
		content_encoding = parse_prop(content_encoding, Props),
		correlation_id = parse_prop(correlation_id, Props),
		message_id = parse_prop(id, Props),
		headers = proplist_to_table(Headers),
		delivery_mode = delivery_type(Props),
		reply_to = parse_prop(reply_to, Props),
		expiration = parse_prop(expiration, Props),
		timestamp = parse_prop(timestamp, Props),
		user_id = parse_prop(user_id, Props),
		app_id = parse_prop(app_id, Props),
		cluster_id = parse_prop(cluster_id, Props),
		priority = parse_prop(priority, Props)
	},

	Publish = #'basic.publish'{ 
		exchange = to_bitstring(Exchange),
		mandatory = parse_prop(mandatory, Props, false),
		immediate = parse_prop(immediate, Props, false),
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
	#'queue.declare'{
		queue=Queue,
		exclusive=parse_prop(exclusive, Config, false),
		durable=parse_prop(durable, Config, false),
		auto_delete=parse_prop(auto_delete, Config, false),
		passive=parse_prop(passive, Config, false),
		nowait=parse_prop(nowait, Config, false)
	}.

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
