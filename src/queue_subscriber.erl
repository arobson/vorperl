%%% @author Alex Robson
%%% @copyright appendTo, 2012
%%% @doc
%%%
%%% @end
%%% @license MIT
%%% Created January 16, 2012 by Alex Robson

-module(queue_subscriber).

-export([start_link/4, init/4, content_provider/4, route_to/2, stop/1]).

-include("amqp_client.hrl").

-include("amqp.hrl").

-define(HOST, amqp).
-define(SERVER, ?MODULE).

-record(state, { 
	queue,
	tag,
	router,
	content_providers = dict:new(),
	channel}).

%%===================================================================
%%% API
%%===================================================================

start_link(Queue, RouteTo, Channel, Providers) ->
	spawn_monitor(?SERVER, init, [Queue, RouteTo, Channel, Providers]).

init(Queue, RouteTo, Channel, Providers) ->
	Sub = #'basic.consume'{queue=Queue},
	#'basic.consume_ok'{consumer_tag = Tag} = 
		amqp_channel:call(Channel, Sub),
	gen_server:cast(vorperl_server, {new_subscription, Queue, self()}),
	loop(#state{
		queue=Queue, 
		router=RouteTo, 
		tag=Tag, 
		channel=Channel, 
		content_providers=Providers}).

content_provider(Pid, ContentProvider, Encoder, Decoder) ->
	Pid ! {content_provider, ContentProvider, Encoder, Decoder}.

route_to(Pid, RouteTo) ->
	Pid ! {route, RouteTo}.

stop(Pid) ->
	Pid ! stop.

%%===================================================================
%%% Internal
%%===================================================================

decode(Envelope, State) ->
	Body = iolist_to_binary(Envelope#envelope.body),
	Providers = State#state.content_providers,
	ContentType = Envelope#envelope.content_type,
	Decoded = 
		case dict:is_key(ContentType, State#state.content_providers) of
			true -> 
				{_, Decoder} = dict:fetch( ContentType, Providers ),
				Decoder(Envelope#envelope.body);
			_ -> Body
		end,
	Envelope#envelope{ body = Decoded }.

handle(#'basic.consume_ok'{}, State) ->
	{ok, State};

handle(#'basic.cancel_ok'{}, _State) ->
	stop;

handle( {route, RouteTo}, State) ->
	{ok, State#state{ router = RouteTo }};

handle( {content_provider, ContentType, Encoder, Decoder}, State) ->
	{ok, State#state{ content_providers = 
		dict:store(ContentType, {Encoder, Decoder}, State#state.content_providers)
	}};

handle(stop, State) ->
	Channel = State#state.channel,
	Tag = State#state.tag,
	Cancel = #'basic.cancel'{ consumer_tag=Tag },
	amqp_channel:call(Channel, Cancel),
	stop;

handle( {Deliver, Msg}, State ) ->
	RouteTo = State#state.router,
	Envelope = amqp_util:prep_envelope( Deliver, Msg, State#state.queue, State#state.channel ),
	Decoded = decode(Envelope, State),
	case RouteTo of
		X when is_function(X, 1) -> 
			X(Decoded);
		X when is_pid(X) -> 
			X ! Decoded;
		{M, F} -> apply(M, F, Decoded)
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
