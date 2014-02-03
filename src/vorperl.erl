%%% @author Alex Robson
%%% @copyright 2012
%%% @doc
%%%
%%% @end
%%% @license MIT
%%% Created January 16, 2012 by Alex Robson

-module(vorperl).

-export([
	bind/3,
	broker/0,
	broker/2, 
	content_provider/3,
	exchange/2,
	publish/2, 
	publish/3,
	publish/4,
	queue/2,
	start/0,
	start_subscription/1,
	stop_subscription/1,
	topology/3
	]).

-include("amqp.hrl").

-define(DEFAULT, "default").

%%===================================================================
%%% API
%%===================================================================

bind(Source, Destination, Topic) ->
	case is_exchange(Destination) of
		true -> bind_exchange(?DEFAULT, Source, Destination, Topic);
		_ -> bind_queue(?DEFAULT, Source, Destination, Topic)
	end.

broker() -> broker(?DEFAULT, []).

broker(Name, Properties) ->vrpl_configuration:store_broker(Name, Properties).

content_provider(ContentType, Encoder, Decoder) ->
	vrpl_configuration:store_serializer(ContentType, {Encoder, Decoder}).

% configured exchange
exchange(Exchange, Properties) -> vrpl_exchange:define(Exchange, Properties).

publish(Exchange, Message) ->
	publish(
		Exchange, 
		Message, 
		<<"">>
	).

publish(Exchange, Message, RoutingKey) ->
	publish(
		Exchange, 
		Message,
		RoutingKey, 
		[]
	).

publish(Exchange, Message, RoutingKey, Properties) ->
	vrpl_exchange:publish(
		Exchange,
		Message,
		RoutingKey,
		Properties
	).

queue(Queue, Properties) -> vrpl_queue:define(Queue, Properties).

start() -> application:start(vorperl).

start_subscription(Queue) -> vrpl_queue:start_subscription(Queue).

stop_subscription(Queue) -> vrpl_queue:stop_subscription(Queue).

topology({exchange, ExchangeName, ExchangeProps}, 
		 {queue, QueueName, QueueProps}, Topic) ->
	exchange(ExchangeName, ExchangeProps),
	queue(QueueName, QueueProps),
	bind(ExchangeName, QueueName, Topic).

%% ===================================================================
%%  Internal
%% ===================================================================

bind_exchange(Broker, Source, Destination, "") ->
	Channel = vrpl_channel:get(Broker, control),
	Binding = #'exchange.bind'{
		destination=amqp_util:to_bitstring(Destination), 
		source=amqp_util:to_bitstring(Source)},
	amqp_channel:call(Channel, Binding);

bind_exchange(Broker, Source, Destination, Topic) ->
	Channel = vrpl_channel:get(Broker, control),
	Binding = #'exchange.bind'{
		destination=amqp_util:to_bitstring(Destination), 
		source=amqp_util:to_bitstring(Source),
		routing_key=amqp_util:to_bitstring(Topic)},
	amqp_channel:call(Channel, Binding).

bind_queue(Broker, Source, Destination, "") ->
	Channel = vrpl_channel:get(Broker, control),
	Binding = #'queue.bind'{
		queue=amqp_util:to_bitstring(Destination), 
		exchange=amqp_util:to_bitstring(Source)},
	amqp_channel:call(Channel, Binding);

bind_queue(Broker, Source, Destination, Topic) ->
	Channel = vrpl_channel:get(Broker, control),
	Binding = #'queue.bind'{
		queue=amqp_util:to_bitstring(Destination), 
		exchange=amqp_util:to_bitstring(Source),
		routing_key=amqp_util:to_bitstring(Topic)},
	amqp_channel:call(Channel, Binding).

is_exchange(Name) -> 
	case vrpl_configuration:get_exchange(Name) of
		undefined -> false;
		_ -> true
	end.