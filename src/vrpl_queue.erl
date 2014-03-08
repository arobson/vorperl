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
	last_nack = 0,
	count=0
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

handle_cast({ack, Tag}, #state{pending=Pending, channel=Channel}=State) ->
	Count = Pending#deliveries.count,
	Delivered = Pending#deliveries.delivered,
	Delivered2 = ordsets:del_element({t, Tag}, Delivered),
	Pending2 = Pending#deliveries{delivered=Delivered2},
	Pending3 = if
		Count >= 100 ->
			{LastAck, LastNack} = check_tags(Pending2, Channel),
			Pending2#deliveries{count=0, last_ack=LastAck, last_nack=LastNack};
		true ->
			Pending2#deliveries{count=Count+1}
	end,
	{noreply, State#state{pending=Pending3}};

handle_cast({nack, Tag}, #state{pending=Pending, channel=Channel}=State) ->
	Pending2 = Pending#deliveries{nacks=ordsets:add_element({t, Tag}, Pending#deliveries.nacks)},
	Count = Pending#deliveries.count,
	Delivered = Pending#deliveries.delivered,
	Delivered2 = ordsets:del_element({t, Tag}, Delivered),
	Pending2 = Pending#deliveries{delivered=Delivered2},
	Pending3 = if
		Count >= 100 ->
			{LastAck, LastNack} = check_tags(Pending2, Channel),
			Pending2#deliveries{count=0, last_ack=LastAck, last_nack=LastNack};
		true ->
			Pending2#deliveries{count=Count+1}
	end,

	{noreply, State#state{pending=Pending3}};

handle_cast(_Msg, State) ->
	{noreply, State}.

handle_info({'DOWN', Ref, process, _Pid, _Info}, #state{monitor=Ref}=State) ->
	{noreply, State};

handle_info({#'basic.deliver'{delivery_tag=Tag}=Deliver, #amqp_msg{}=Msg}, 
				#state{router=Router, channel=Channel, name=Queue, pending=Pending}=State) ->
	Envelope = amqp_util:prep_envelope( Deliver, Msg, Queue, Channel ),
	Decoded = decode(Envelope),
	case Router of
		X when is_function(X, 1) -> 
			X(Decoded);
		X when is_pid(X) -> 
			X ! Decoded;
		{M, F} -> apply(M, F, Decoded)
	end,
	Pending2 = Pending#deliveries{delivered=ordsets:add_element({t, Tag}, Pending#deliveries.delivered)},
	{noreply, #state{pending=Pending2}=State};

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

ack(Tag, Multiple, Channel) ->
	Ack = #'basic.ack'{delivery_tag=Tag, multiple=Multiple},
	amqp_channel:call(Channel, Ack).

nack(Tag, Multiple, Channel) ->
	Ack = #'basic.nack'{delivery_tag=Tag, multiple=Multiple, requeue=true},
	amqp_channel:call(Channel, Ack).

call(Queue, Message) -> 
	Pid = vrpl_process:get({queue, Queue}),
	gen_server:call(Pid, Message).

check_tags(Deliveries, Channel) ->
	LastAck = Deliveries#deliveries.last_ack,
	LastNack = Deliveries#deliveries.last_nack,
	{NextTag, {StartNack, EndNack}} = next_tags(Deliveries),
	handle_tags(NextTag-1, LastAck, StartNack, EndNack, LastNack, Channel).
	
%% no pending acks, no pending nacks
%% ack 0, true to acknowledge all outstanding messages to broker
handle_tags(0, LastAck, 0, 0, LastNack, Channel) -> 
	ack(0, true, Channel),
	{LastAck, LastNack};

%% pending acks, no pending nacks
%% when the next ack is greater than the previous nack (prevent overlap)
handle_tags(NextAck, _LastAck, 0, 0, LastNack, Channel)
		when NextAck > LastNack ->
	ack(NextAck, true, Channel),
	{NextAck, LastNack};

%% no pending acks
%% if the last ack is less than where the nack run starts
%% ack up that point before nacking to the end
handle_tags(0, LastAck, StartNack, EndNack, _LastNack, Channel) 
		when LastAck < StartNack ->
	case StartNack - LastAck of
		1 -> 
			nack(EndNack, true, Channel),
			{LastAck, EndNack};
		_ ->
			ack(StartNack-1, true, Channel),
			nack(EndNack, true, Channel),
			{StartNack-1, EndNack}
	end;
	
%% pending acks & nacks
handle_tags(NextAck, _LastAck, StartNack, EndNack, LastNack, Channel) 
		when NextAck < StartNack ->
	case StartNack - NextAck of
		1 ->
			ack(NextAck, true, Channel),
			nack(EndNack, false, Channel),
			{NextAck, EndNack};
		_ ->
			ack(NextAck, true, Channel),
			{NextAck, LastNack}
	end;

handle_tags(NextAck, LastAck, StartNack, EndNack, _LastNack, Channel) 
		when NextAck > EndNack ->
	case StartNack - LastAck of
		1 ->
			nack(EndNack, true, Channel),
			ack(NextAck, true, Channel),
			{NextAck, EndNack};
		_ ->
			ack(StartNack-1, true, Channel),
			nack(EndNack, true, Channel),
			ack(NextAck, true, Channel),
			{NextAck, EndNack}
	end.

next_tags(#deliveries{delivered=Delivered, nacks=Nacks}) -> 
	next_tags(ordsets:to_list(Delivered), ordsets:to_list(Nacks)).

next_tags([],[]) -> {0,{0,0}};
next_tags([],Nacks) -> {0,get_consecutive_range(Nacks)};
next_tags([A|_],[]) -> {A,{0,0}};
next_tags([A|_],Nacks) -> {A,{get_consecutive_range(Nacks)}}.

get_consecutive_range(List) -> get_consecutive_range(List, 0, 0).

get_consecutive_range([],Start,Finish) -> {Start,Finish};
get_consecutive_range([H|T], 0, Finish) ->
	get_consecutive_range(T, H, Finish);
get_consecutive_range([H|T], Start, Finish) when H-Finish =:= 1 ->
	get_consecutive_range(T, Start, H);
get_consecutive_range(_, Start, Finish) -> {Start, Finish}.

% get_consecutive_range(List) ->
% 	lists:foldl(fun(Y,{X1,X2}) ->
% 		if 
% 			X1 =:= 0 -> {Y,Y}; 
% 			Y-X2 =:= 1 -> {X1,Y}; 
% 			true -> {X1,X2} 
% 		end 
% 	end, {0,0}, List).

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
	