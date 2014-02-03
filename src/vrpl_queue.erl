%%% @author Alex Robson
%%% @copyright 2012
%%% @doc
%%%
%%% @end
%%% @license MIT
%%% Created January 16, 2012 by Alex Robson

-module(vrpl_queue).

-behavior(gen_server).

-export([start_link/2, init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-export([define/2, start_subscription/1, stop/1, stop_subscription/1]).

-include("amqp.hrl").

-define(DEFAULT, "default").
-define(HOST, amqp).
-define(SERVER, ?MODULE).

-record(deliveries, {
	delivered = ordsets:new(),
	nacks = ordsets:new(),
	last_ack = 0,
	last_nack = 0
	}).

-record(state, {channel, props, name, monitor, router, tag, pending=#deliveries{}}).

%%===================================================================
%%% API
%%===================================================================

define(Queue, Properties) ->
	vrpl_configuration:store_queue(Queue, Properties),
	case vrpl_process:get({queue, Queue}) of
		undefined -> 
			vrpl_queues:add(Queue, Properties);
		Pid when is_pid(Pid) -> Pid
	end.

stop(Queue) -> call(Queue, stop).

start_subscription(Queue) -> call(Queue, subscribe).

stop_subscription(Queue) -> call(Queue, unsubscribe).

%%===================================================================
%%% gen_server
%%===================================================================

start_link(Queue, Properties) ->
	gen_server:start_link(?MODULE, [Queue, Properties], []).

init([Queue, Properties]) ->
	vrpl_process:store({queue, Queue}),
	State = setup(Queue, Properties),
	{ok, State#state{props=Properties}}.

handle_call(stop, _From, State) ->
	{stop, normal, stopped, State};
 
handle_call(subscribe, _From, 
				#state{name=Queue, channel=Channel}=State) ->
	BinaryName = amqp_util:to_bin(Queue),
	Sub = #'basic.consume'{queue=BinaryName},
	#'basic.consume_ok'{consumer_tag=Tag} = amqp_channel:call(Channel, Sub),
	{reply, ok, State#state{tag=Tag}};

handle_call(unsubscribe, _From,
				#state{channel=Channel, tag=Tag}=State) ->
	Cancel = #'basic.cancel'{consumer_tag=Tag},
	amqp_channel:call(Channel, Cancel),
	{reply, ok, State#state{tag=undefined}};

handle_call(_Request, _From, State) ->
	{reply, ok, State}.

handle_cast(_Msg, State) ->
	{noreply, State}.

handle_info({'DOWN', Ref, process, _Pid, _Info}, #state{monitor=Ref}=State) ->
	{noreply, State};

handle_info({#'basic.deliver'{}=Deliver, #amqp_msg{}=Msg}, 
				#state{router=Router, channel=Channel, name=Queue}=State) ->
	Envelope = amqp_util:prep_envelope( Deliver, Msg, Queue, Channel ),
	Decoded = decode(Envelope),
	case Router of
		X when is_function(X, 1) -> 
			X(Decoded);
		X when is_pid(X) -> 
			X ! Decoded;
		{M, F} -> apply(M, F, Decoded)
	end,
	{noreply, State};

handle_info(#'basic.consume_ok'{consumer_tag=Tag}, State) ->
	{noreply, State#state{tag=Tag}};

handle_info(#'basic.cancel_ok'{}, State) ->
	{noreply, State#state{tag=undefined}};

handle_info(_Info, State) ->
	io:format("Queue Subscriber received a message it doesn't understand. ~n"),
 	{noreply, State}.
 
terminate(_Reason, _State) ->
	ok.
 
code_change(_OldVsn, State, _Extra) ->
	{ok, State}.

%%===================================================================
%%% Internal
%%===================================================================

call(Queue, Message) -> 
	Pid = vrpl_process:get({queue, Queue}),
	gen_server:call(Pid, Message).

decode(Envelope) ->
	Body = iolist_to_binary(Envelope#envelope.body),
	ContentType = Envelope#envelope.content_type,
	Decoded = vrpl_message_util:decode(Body, ContentType),
	Envelope#envelope{ body = Decoded }.

ensure_monitor(#state{channel = Channel, monitor = Monitor} = State) ->
	case Monitor of
		undefined -> ok;
		_ -> demonitor(Monitor)
	end,
	Ref = monitor(process, Channel),
	State#state{monitor=Ref}.

handle_message(Queue, #envelope{ack=Ack}=X) ->
	Ack(),
	io:format("Received on '~p': ~p~n", [Queue, X]).

setup(#state{name = Queue, props = Props, channel = Channel} = State) ->
	Config = amqp_util:parse_proplist(Props),
	BinaryName = amqp_util:to_bitstring(Queue),
	Declaration = amqp_util:queue_declare(BinaryName, Config),
	amqp_channel:call(Channel, Declaration),
	State;

setup(Queue) ->
	Props = vrpl_configuration:get_exchange(Queue),
	setup(Queue, Props).

setup(Queue, Props) ->
	Broker = proplists:get_value(broker, Props, ?DEFAULT),
	Channel = vrpl_channel:get({queue, Queue}, Broker),
	setup(Queue, Props, Channel).

setup(Queue, Props, Channel) ->
	Router = proplists:get_value(route, Props, fun(X) -> handle_message(Queue, X) end),
	State = #state{name = Queue, props = Props, channel = Channel, router=Router},
	ensure_monitor(setup(State)).
	