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
			exchange_config_to_bin/1, 
			queue_config_to_bin/1, 
			to_bin/1, 
			topology_to_bin/1
		]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-include("amqp.hrl").

-include("amqp_client.hrl").

broker_to_bin(undefined) ->
	undefined;
broker_to_bin(Broker=#broker{}) ->
	Broker#broker{
		user = to_bin(Broker#broker.user),
		password = to_bin(Broker#broker.password),
		host = to_bin(Broker#broker.host),
		virtual_user = to_bin(Broker#broker.virtual_host),
	}.

exchange_config_to_bin(undefined) ->
	undefined;
exchange_config_to_bin(Config=#exchange_config{}) ->
	Config#exchange_config{
		type=to_bin(Config#exchange_config.type)
	}.

queue_config_to_bin(undefined) ->
	undefined;
queue_config_to_bin(Config=#queue_config{}) ->
	Config#queue_config{
	}.

topology_to_bin(Topology=#topology{}) ->
	Topology#topology{
		exchange=to_bin(Topology#topology.exchange),
		queue=to_bin(Topology#topology.queue),
		topic=to_bin(Topology#topology.topic),
		exchange_config=exchange_config_to_bin(Topology#topology.exchange_config),
		queue_config=queue_config_to_bin(Topology#topology.queue_config)
	}.

to_bin(X) when is_atom(X) ->
	undefined;
to_bin(X) when is_list(X) ->
	list_to_bitstring(X);
to_bin(X) when is_bitstring(X) ->
	X.