%%% @author Alex Robson
%%% @copyright Alex Robson, 2012
%%% @doc
%%%
%%% @end
%%% @license MIT
%%% Created January 16, 2012 by Alex Robson

-module(amqp).

-behavior(gen_server).

-export([bind/3, define/1, send/2, send/3]).

-export([start_link/0, init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-include("amqp_client.hrl").

-include("amqp.hrl").

-define(SERVER, ?MODULE).

-record(state, {
	connection, 
	router, 
	control_channel, 
	exchange_channel, 
	queue_channels, 
	subscriptions}).

%%===================================================================
%%% API
%%===================================================================

bind( Exchange, Queue, Topic ) ->
	gen_server:cast(?SERVER, {bind, Exchange, Queue, Topic}).

%% Invalid topology
declare( #topology{ exchange=undefined, queue=undefined }) ->
	bad_topology;

%% Declaring a queue only
declare( Topology=#topology{ exchange_config=undefined }) ->
	gen_server:cast(?SERVER, {create_queue, 
		Topology#topology.queue, 
		Topology#topology.queue_config}),

	case Topology#topology.exchange of
		undefined -> ok;
		Exchange -> bind(
			Exchange, 
			Topology#topology.queue, 
			Topology#topology.topic)
		end;

%% Declaring an exchange only
declare( Topology=#topology{ queue_config=undefined }) ->
	gen_server:cast(?SERVER, {create_exchange, 
		Topology#topology.exchange, 
		Topology#topology.exchange_config}),

	case Topology#topology.queue of
		undefined -> ok;
		Queue -> bind(
			Topology#topology.exchange,
			Queue, 
			Topology#topology.topic)
		end;
	
%% Declaring an exchange, queue and binding
declare( Topology=#topology{} ) ->
	gen_server:cast(?SERVER, {create_exchange, 
		Topology#topology.exchange, 
		Topology#topology.exchange_config}),

	gen_server:cast(?SERVER, {create_queue, 
		Topology#topology.queue, 
		Topology#topology.queue_config}),

	bind(Topology#topology.exchange, 
		Topology#topology.queue,
		Topology#topology.topic).

send(Exchange, Message) ->
	send(Exchange, Message,  <<"">>).
	
send(Exchange, Message, RoutingKey) ->
	send(Exchange, Message, RoutingKey, #message_flags{}).

send(Exchange, Message, RoutingKey, Flags) ->
	gen_server:cast(?SERVER, {send, 
		amqp_util:to_bin(Exchange), 
		Message, 
		amqp_util:to_bin(RoutingKey), 
		Flags}).

define(Topology=#topology{}) ->
	declare(amqp_util:topology_to_bin(Topology)).

%%===================================================================
%%% gen_server
%%===================================================================

start_link() ->
	gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

init([]) ->
	Router = fun(X)-> 
			io:format("acking message~n"),
			Ack = X#envelope.ack,
			Ack()
		end,
	case connect() of
		{ok, Connection} ->
			State = new_state(Connection),
			{ok, State#state{router=Router}};
		_ ->
			{stop}
	end.

handle_call(stop, _From, State) ->
  {stop, normal, stopped, State};
 
handle_call(state, _From, State) ->
  {reply, State, State};
 
handle_call(_Request, _From, State) ->
  {reply, ok, State}.
 
handle_cast({create_exchange, Exchange, ExchangeConfig}, State) ->
  {noreply, declare_exchange(Exchange, ExchangeConfig, State)};

handle_cast({create_queue, Queue, QueueConfig}, State) ->
  {noreply, declare_queue(Queue, QueueConfig, State)};

handle_cast({bind, Exchange, Queue, Topic}, State) ->
	{noreply, bind(
		amqp_util:to_bin(Exchange), 
		amqp_util:to_bin(Queue), 
		amqp_util:to_bin(Topic), 
		State)};

handle_cast({send, Exchange, MessageBody, RoutingKey, Flags}, State) ->
	{noreply, send_message(Exchange, MessageBody, RoutingKey, Flags, State)};

handle_cast(_Msg, State) ->
  {noreply, State}.
 
handle_info(_Info, State) ->
  {noreply, State}.
 
terminate(_Reason, _State) ->
  ok.
 
code_change(_OldVsn, State, _Extra) ->
  {ok, State}.


%%===================================================================
%%% Internal
%%===================================================================

bind(Exchange, Queue, RoutingKey, State) ->
	{Channel, State2} = control_channel(State),
	Binding = #'queue.bind'{
		queue=Queue, 
		exchange=Exchange, 
		routing_key=RoutingKey},
	#'queue.bind_ok'{} = amqp_channel:call(Channel, Binding),
	State2.



declare_exchange(Exchange, ExchangeConfig, State) ->
	Declare = #'exchange.declare'{
		exchange=Exchange,
		type=ExchangeConfig#exchange_config.type,
		durable=ExchangeConfig#exchange_config.durable,
		auto_delete=ExchangeConfig#exchange_config.auto_delete
	},
	{Channel, State2}=control_channel(State),
	io:format("exchange ~p~n", [Declare]),
	amqp_channel:call(Channel, Declare),
	State2.

declare_queue(Queue, QueueConfig, State) ->
	Declare = #'queue.declare'{
		queue=Queue,
		durable=QueueConfig#queue_config.durable,
		auto_delete=QueueConfig#queue_config.auto_delete
	},
	{Channel, State2}=control_channel(State),
	amqp_channel:call(Channel, Declare),
	
	% subscribe
	{QueueChannel, State3} = queue_channel(Queue, State2),
	subscription_sup:start_subscription(Queue, State3#state.router, QueueChannel),
	Queue_Channels = dict:append(Queue, QueueChannel, State3#state.queue_channels),
	
	State3#state{queue_channels = Queue_Channels}.


			
new_state(Connection) ->
	#state{
		connection = Connection,
		control_channel = undefined,
		exchange_channel = undefined,
		queue_channels = dict:new(),
		subscriptions = dict:new()
		}.

queue_channel(Queue, State) ->
	Channels=State#state.queue_channels,
	case dict:is_key(Queue, Channels) of
		true -> {dict:fetch(Queue, Channels), State};
		false -> 
			NewChannel = get_channel(State),
			NewChannels = dict:append(Queue, NewChannel, Channels),
			{NewChannel, State#state{queue_channels=NewChannels}}
	end.

send_message(Exchange, Message, RoutingKey, _Flags, State) ->
	{Channel, State2} = send_channel(State),
	Publish = #'basic.publish'{exchange=Exchange, routing_key=RoutingKey},
	amqp_channel:cast(Channel, Publish, #amqp_msg{payload=Message}),
	State2.

send_channel(State)->
	case State#state.exchange_channel of
		undefined -> 
			NewChannel = get_channel(State),
			{NewChannel, State#state{exchange_channel=NewChannel}};
		Channel -> {Channel, State}
	end.


