%%% @author Alex Robson
%%% @copyright appendTo, 2012
%%% @doc
%%%
%%% @end
%%% @license MIT
%%% Created January 16, 2012 by Alex Robson

-module(vorperl).

-export([
	bind/3,
	broker/0,
	broker/1, 
	content_provider/3,
	exchange/1,
	exchange/2,
	on_return/1,
	queue/1,
	queue/2,
	route_to/1,
	send/2, 
	send/3,
	send/4,
	stop_subscription/1,
	subscribe_to/1,
	subscribe_to/2,
	topology/3
	]).

-define(SERVER, vorperl_server).

%%===================================================================
%%% API
%%===================================================================

bind( Source, Destination, Topic ) ->
	gen_server:cast(?SERVER, {
		bind, 
		Source, 
		Destination, 
		Topic}).

broker() ->
	connection_pool:add_broker().

broker(Props) ->
	connection_pool:add_broker(Props).

content_provider( ContentType, Encoder, Decoder ) ->
	gen_server:cast(?SERVER, {ContentType, Encoder, Decoder}).

% default exchange
exchange(Exchange) ->
	exchange(Exchange, []).

% configured exchange
exchange(Exchange, Options) ->
	gen_server:cast(?SERVER, {
		create_exchange, 
		Exchange, 
		Options
	}).

on_return(Handler) ->
	gen_server:cast(connection_pool, {
		on_return,
		Handler
	}).

queue(Queue) ->
	queue(Queue, []).

queue(Queue, Options) ->
	gen_server:cast(?SERVER, {
		create_queue, 
		Queue, 
		Options
	}).

route_to(Router) ->
	gen_server:cast(?SERVER, {
		route,
		Router
	}).

send(Exchange, Message) ->
	send(
		Exchange, 
		Message, 
		<<"">>
	).

send(Exchange, Message, RoutingKey) ->
	send(
		Exchange, 
		Message,
		RoutingKey, 
		[]
	).

send(Exchange, Message, RoutingKey, Properties) ->
	gen_server:cast(?SERVER, {
		send, 
		Exchange, 
		Message,
		RoutingKey, 
		Properties
	}).

stop_subscription(Queue) ->
	gen_server:cast(?SERVER, {
		stop_subscription,
		Queue
	}).

subscribe_to(Queue) ->
	gen_server:cast(?SERVER, {
		subscribe,
		Queue
	}).

subscribe_to(Queue, RouteTo) ->
	gen_server:cast(?SERVER, {
		subscribe,
		Queue,
		RouteTo
	}).

topology({exchange, ExchangeName, ExchangeProps}, 
		 {queue, QueueName, QueueProps}, Topic) ->
	exchange(ExchangeName, ExchangeProps),
	queue(QueueName, QueueProps),
	bind(ExchangeName, QueueName, Topic).