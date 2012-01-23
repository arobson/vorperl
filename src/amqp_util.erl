%%% @author Alex Robson
%%% @copyright Alex Robson, 2012
%%% @doc
%%%
%%% @end
%%% @license MIT
%%% Created January 20, 2012 by Alex Robson

-module(amqp_util).

-export([ 
			broker_to_bin/1,
			exchange_declare/2,
			prep_message/2,
			parse_proplist/1,
			queue_declare/2,		
			to_bin/1
		]).

-include("amqp.hrl").

-include("amqp_client.hrl").

broker_to_bin(undefined) ->
	undefined;
broker_to_bin(Broker=#broker{}) ->
	Broker#broker{
		user = to_bin(Broker#broker.user),
		password = to_bin(Broker#broker.password),
		host = Broker#broker.host,
		virtual_host = to_bin(Broker#broker.virtual_host)
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

parse_dict(undefined) ->
	undefined;
parse_dict(D) ->
	dict:from_list([ {X,to_bin(Y)} || {X,Y} <- dict:to_list(D) ]).

parse_prop(Prop, Props) ->
	parse_prop(Prop, Props, undefined).
parse_prop(Prop, Props, Default) ->
	to_bin(proplists:get_value(Prop, Props, Default)).

parse_proplist(L) ->
	Unfolded = proplists:unfold(L),
	[{X, to_bin(Y)} || {X,Y} <- Unfolded].

prep_message(Exchange, RoutingKey, Props) ->
	
	AmqpProps = #'P_basic'{
		content_type = parse_prop(content_type, Props, "text/plain"),
		content_encoding = parse_prop(content_encoding, Props),
		correlation_id = parse_prop(correlation_id, Props),
		message_id = parse_prop(id, Props),
		headers = parse_dict(parse_prop(headers, Props)),
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
		exchange = to_bin(Exchange),
		mandatory = parse_prop(mandatory, Props, false),
		immediate = parse_prop(immediate, Props, false),
		routing_key = to_bin(RoutingKey)
	},

	{AmqpProps, Publish}.

queue_declare(Queue, Config) ->
	#'queue.declare'{
		queue=Queue,
		exclusive=parse_prop(exclusive, Config, false),
		durable=parse_prop(durable, Config, false),
		auto_delete=parse_prop(auto_delete, Config, false),
		passive=parse_prop(passive, Config, false),
		nowait=parse_prop(nowait, Config, false)
	}.

to_bin(X) when is_list(X) ->
	list_to_bitstring(X);
to_bin(X) when is_bitstring(X) ->
	X;
to_bin(X) ->
	X.