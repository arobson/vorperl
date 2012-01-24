%%% @author Alex Robson
%%% @copyright Alex Robson, 2012
%%% @doc
%%%
%%% @end
%%% @license MIT
%%% Created January 16, 2012 by Alex Robson

-module(vorperl).

-behavior(gen_server).

-export([
	bind/3,
	broker/0,
	broker/1, 
	exchange/1,
	exchange/2,
	queue/1,
	queue/2,
	send/2, 
	send/3,
	send/4]).

-export([start_link/0, init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-include("amqp.hrl").

-define(SERVER, ?MODULE).

-record(state, {
	router, 
	subscriptions,
	control_channel,
	declarations = []}).

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

% default exchange
exchange(Exchange) ->
	exchange(Exchange, []).

% configured exchange
exchange(Exchange, Options) ->
	Parsed = amqp_util:parse_proplist(Options),
	gen_server:cast(?SERVER, {
		create_exchange, 
		amqp_util:to_bin(Exchange), 
		Parsed
	}).

queue(Queue) ->
	queue(Queue, []).

queue(Queue, Options) ->
	Parsed = amqp_util:parse_proplist(Options),
	gen_server:cast(?SERVER, {
		create_queue, 
		amqp_util:to_bin(Queue), 
		Parsed
	}).

send(Exchange, Message) ->
	send(
		Exchange, 
		Message, 
		""
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
		amqp_util:to_bin(Exchange), 
		Message,
		amqp_util:to_bin(RoutingKey), 
		Properties
	}).

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
	{ok, #state{router=Router}}.

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

handle_cast({bind, Source, Target, Topic}, State) ->
	{noreply, bind(
		amqp_util:to_bin(Source), 
		amqp_util:to_bin(Target), 
		amqp_util:to_bin(Topic), 
		State)};

handle_cast({send, Exchange, MessageBody, RoutingKey, Props}, State) ->
	{noreply, send_message(Exchange, MessageBody, RoutingKey, Props, State)};

handle_cast(_Msg, State) ->
  {noreply, State}.

handle_info({'DOWN', _Ref, process, _Pid, _Info}, State) ->
	Channel = connection_pool:get_channel(control),
	replay_declarations(State#state.declarations, Channel, State),
	{noreply, State#state{ control_channel = monitor(process, Channel) }};

handle_info(_Info, State) ->
  {noreply, State}.
 
terminate(_Reason, _State) ->
  ok.
 
code_change(_OldVsn, State, _Extra) ->
  {ok, State}.


%%===================================================================
%%% Internal
%%===================================================================

bind(Source, Target, RoutingKey, State) ->
	Channel= connection_pool:get_channel(control),
	Binding = #'queue.bind'{
		queue=Target, 
		exchange=Source, 
		routing_key=RoutingKey},
	amqp_channel:call(Channel, Binding),
	State2 = State#state{ declarations =
		lists:append(State#state.declarations, [{bind, Binding}])},
	ensure_monitor(Channel, State2).

declare_exchange(Exchange, Config, State) -> 
	Declare = amqp_util:exchange_declare(Exchange, Config),
	Channel= connection_pool:get_channel(control),
	amqp_channel:call(Channel, Declare),
	State2 = State#state{ declarations =
		lists:append(State#state.declarations, [{exchange, Declare}])},
	ensure_monitor(Channel, State2).

declare_queue(Queue, Config, State) ->
	Declare = amqp_util:queue_declare(Queue, Config),
	Channel = connection_pool:get_channel(control),
	amqp_channel:call(Channel, Declare),
	subscribe(Queue, State),
	State2 = State#state{ declarations =
		lists:append(State#state.declarations, [{queue, Queue, Declare}])},
	ensure_monitor(Channel, State2).

encode_message(Msg, _Flags) ->
	amqp_util:to_bin(Msg).

ensure_monitor(Channel, State) ->
	State#state{ control_channel = 
		case State#state.control_channel of
			undefined -> monitor(process, Channel);
			_ -> State#state.control_channel
		end }.

replay_declarations([], _Channel, _State) ->
	ok;
replay_declarations([D|T], Channel, State) ->
	replay_declarations(D, Channel, State),
	replay_declarations(T, Channel, State);

replay_declarations({queue, Queue, Declaration}, Channel, State) ->
	amqp_channel:call(Channel, Declaration),
	subscribe(Queue, State);

replay_declarations({_Type, Declaration}, Channel, _State) ->
	amqp_channel:call(Channel, Declaration).

send_message(Exchange, Message, RoutingKey, Props, State) ->
	Channel= connection_pool:get_channel(send),
	Payload = encode_message(Message, Props),
	{AmqpProps, Publish} = amqp_util:prep_message(Exchange, RoutingKey, Props),
	Envelope = #amqp_msg{props = AmqpProps, payload = Payload},
	amqp_channel:cast(Channel, Publish, Envelope),
	State.

subscribe(Queue, State) ->
	QueueChannel = connection_pool:get_channel(Queue),
	subscription_sup:start_subscription(Queue, State#state.router, QueueChannel).