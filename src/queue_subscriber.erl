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
		{ Deliver, Msg } ->
			RouteTo = State#state.router,
			Envelope = amqp_util:prep_envelope( Deliver, Msg, State#state.queue, State#state.channel ),
			case RouteTo of
				X when is_function(X, 1) -> 
					X(Envelope);
				X when is_pid(X) -> 
					X ! Envelope;
				{M, F} -> apply(M, F, Envelope)
			end,
			loop(State)
	end.