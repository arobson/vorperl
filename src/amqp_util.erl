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
			prep_message/2,
			parse_proplist/1,			
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

delivery_type(#message_flags{persist=Persist}) ->
	case Persist of
		true -> 2;
		_ -> 1
	end.

prep_message(Exchange, X) ->
	
	Props = #'P_basic'{
		content_type = to_bin(X#message_flags.content_type),
		content_encoding = to_bin(X#message_flags.content_encoding),
		correlation_id = to_bin(X#message_flags.correlation_id),
		message_id = to_bin(X#message_flags.id),
		headers = parse_dict(X#message_flags.headers),
		delivery_mode = delivery_type(X),
		reply_to = to_bin(X#message_flags.reply_to),
		expiration = X#message_flags.expiration,
		timestamp = X#message_flags.timestamp,
		user_id = to_bin(X#message_flags.user_id),
		app_id = to_bin(X#message_flags.app_id),
		cluster_id = to_bin(X#message_flags.cluster_id),
		priority = X#message_flags.priority
	},

	Publish = #'basic.publish'{ 
		exchange = to_bin(Exchange),
		mandatory = X#message_flags.mandatory,
		immediate = X#message_flags.immediate,
		routing_key = to_bin(X#message_flags.key)
	},

	{Props, Publish}.

parse_dict(D) ->
	dict:from_list([ {X,to_bin(Y)} || {X,Y} <- dict:to_list(D) ]).

parse_proplist(L) ->
	Unfolded = proplists:unfold(L),
	Transformed = [{X, to_bin(Y)} || {X,Y} <- Unfolded].


to_bin(X) when is_list(X) ->
	list_to_bitstring(X);
to_bin(X) when is_bitstring(X) ->
	X;
to_bin(X) ->
	X.