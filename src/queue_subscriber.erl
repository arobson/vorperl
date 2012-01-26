%%% @author Alex Robson
%%% @copyright Alex Robson, 2012
%%% @doc
%%%
%%% @end
%%% @license MIT
%%% Created January 16, 2012 by Alex Robson

-module(queue_subscriber).

-export([start_link/3, init/3, route_to/2]).

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
	gen_server:cast(vorperl, {new_subscription, self()}),
	loop(#state{queue=Queue, router=RouteTo, tag=Tag, channel=Channel}).

route_to(Pid, RouteTo) ->
	Pid ! {route, RouteTo}.

%%===================================================================
%%% Internal
%%===================================================================

handle(#'basic.consume_ok'{}, State) ->
	{ok, State};

handle(#'basic.cancel_ok'{}, _State) ->
	stop;

handle( {route, RouteTo}, State) ->
	{ok, State#state{ router = RouteTo }};

handle( {Deliver, Msg}, State ) ->
	RouteTo = State#state.router,
	Envelope = amqp_util:prep_envelope( Deliver, Msg, State#state.queue, State#state.channel ),
	case RouteTo of
		X when is_function(X, 1) -> 
			X(Envelope);
		X when is_pid(X) -> 
			X ! Envelope;
		{M, F} -> apply(M, F, Envelope)
	end,
	{ok, State};

handle( _Whatever, State ) ->
	io:format("Queue Subscriber received a message it doesn't understand. ~n"),
	{ok, State}.


loop(State) ->
	receive
		Message -> 
			case handle(Message, State) of
				{ok, NewState} -> loop(NewState);
				stop -> ok
			end
	end.
