%%% @author Alex Robson
%%% @copyright Alex Robson, 2012
%%% @doc
%%%
%%% @end
%%% @license MIT
%%% Created January 16, 2012 by Alex Robson

-module(queue_subscriber).

-export([start_link/3, init/3]).

-include("amqp_client.hrl").

-include("amqp.hrl").

-define(HOST, amqp).
-define(SERVER, ?MODULE).

-record(state, { 
	queue,
	tag,
	router,
	channel}).

%%===================================================================
%%% API
%%===================================================================

start_link(Queue, RouteTo, Channel) ->
	spawn_monitor(?SERVER, init, [Queue, RouteTo, Channel]).

init(Queue, RouteTo, Channel) ->
	Sub = #'basic.consume'{queue=Queue},
	#'basic.consume_ok'{consumer_tag = Tag} = 
		amqp_channel:call(Channel, Sub),
	loop(#state{queue=Queue, router=RouteTo, tag=Tag, channel=Channel}).

loop(State) ->
	receive
		#'basic.consume_ok'{} ->
			loop(State);
		#'basic.cancel_ok'{} ->
			gen_server:cast(?HOST, {subscription_stopped, State#state.tag}),
			ok;
		{#'basic.deliver'{
				delivery_tag=Tag,
				exchange=Exchange,
				routing_key=Key
			}, Content} ->
				io:format("GOT ME A MESSAGE!~n"),
				RouteTo = State#state.router,
				Envelope = #envelope{
					exchange=Exchange,
					queue=State#state.queue,
					key=Key,
					body=Content,
					ack=get_ack(Tag, State),
					nack=get_nack(Tag, State)
				},
				case is_function(RouteTo, 1) of
					true -> RouteTo(Envelope);
					_ -> RouteTo ! Envelope
				end,
				loop(State)
	end.

get_ack(Tag, State) ->
	fun() -> amqp_channel:cast(State#state.channel, #'basic.ack'{delivery_tag=Tag}) end.
get_nack(Tag, State) ->
	fun() -> amqp_channel:cast(State#state.channel, #'basic.nack'{delivery_tag=Tag}) end.